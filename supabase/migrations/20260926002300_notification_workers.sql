-- Bounded outbox expansion is a database transaction. HTTP delivery is a separate lease.
CREATE FUNCTION public.set_notification_recipients(p_academy uuid,p_recipients jsonb,p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE ctx jsonb; r jsonb; v_email text;
BEGIN
 PERFORM private.require_permission(p_academy,'academy.notification_recipients_write');
 IF jsonb_typeof(p_recipients) IS DISTINCT FROM 'array' OR jsonb_array_length(p_recipients)>200 THEN PERFORM private.fail('INVALID_INPUT','22023'); END IF;
 ctx:=private.cmd_begin(p_academy,'set_notification_recipients',p_operation_key,p_recipients);
 IF ctx ? 'replay' THEN RETURN ctx->'replay'; END IF;
 PERFORM private.lock_academy(p_academy);
 UPDATE private.academy_notification_recipients SET active=false,updated_by=auth.uid() WHERE academy_id=p_academy;
 FOR r IN SELECT value FROM jsonb_array_elements(p_recipients) LOOP
 v_email:=lower(btrim(r->>'email'));
 IF v_email IS NULL OR length(v_email)>320 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
 OR length(r->>'name')>160 THEN PERFORM private.fail('INVALID_EMAIL','22023'); END IF;
 INSERT INTO private.academy_notification_recipients(academy_id,email,display_name,updated_by)
 VALUES(p_academy,v_email,r->>'name',auth.uid()) ON CONFLICT(academy_id,email)
 DO UPDATE SET active=true,display_name=EXCLUDED.display_name,updated_by=auth.uid();
 END LOOP;
 PERFORM private.audit(ctx,'audit','notification_recipients.updated','academy',p_academy);
 RETURN private.cmd_finish(ctx,jsonb_build_object('outcome','UPDATED'));
END;
$$;

CREATE FUNCTION private.notification_recipients(p_event private.notification_events) RETURNS TABLE(email text,language text)
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 WITH booking AS (SELECT b.*,s.coach_id FROM public.bookings b JOIN public.sessions s ON s.academy_id=b.academy_id AND s.id=b.session_id
 WHERE b.id=p_event.booking_id AND b.academy_id=p_event.academy_id), people AS (
 SELECT l.user_id FROM booking b JOIN public.player_links l ON l.academy_id=b.academy_id
 AND l.player_id=b.player_id AND l.revoked_at IS NULL
 AND (l.user_id=b.notification_owner_id OR (b.notification_owner_id IS NULL AND l.is_primary))
 WHERE private.actor_permission(l.user_id,b.academy_id,'bookings.request')
 AND EXISTS(SELECT FROM public.academy_memberships m JOIN private.academy_membership_roles r
 ON r.academy_id=m.academy_id AND r.membership_id=m.id
 WHERE m.academy_id=b.academy_id AND m.user_id=l.user_id AND r.revoked_at IS NULL
 AND r.role_code=CASE l.relationship WHEN 'SELF' THEN 'STUDENT' ELSE 'PARENT' END)
 UNION
 SELECT m.user_id FROM booking b JOIN public.coaches c ON c.academy_id=b.academy_id AND c.id=b.coach_id
 JOIN public.academy_memberships m ON m.academy_id=c.academy_id AND m.id=c.membership_id
 WHERE p_event.event_type<>'BOOKING_REMINDER' AND c.active AND c.deleted_at IS NULL
 AND private.actor_permission(m.user_id,b.academy_id,'attendance.record')
 UNION
 SELECT m.user_id FROM public.academy_memberships m WHERE m.academy_id=p_event.academy_id
 AND p_event.event_type IN ('BOOKING_REQUESTED','BOOKING_SCHEDULED','BOOKING_REJECTED','BOOKING_CANCELLED')
 AND private.actor_permission(m.user_id,m.academy_id,'memberships.invite')
 AND NOT EXISTS(SELECT FROM private.academy_notification_recipients WHERE academy_id=m.academy_id AND active)
 )
 SELECT lower(u.email),p.preferred_language FROM people x JOIN auth.users u ON u.id=x.user_id
 JOIN public.user_profiles p ON p.id=x.user_id WHERE u.email_confirmed_at IS NOT NULL AND u.email IS NOT NULL AND p.status='ACTIVE'
 UNION
 SELECT r.email,a.default_language FROM private.academy_notification_recipients r JOIN public.academies a ON a.id=r.academy_id
 WHERE r.academy_id=p_event.academy_id AND r.active AND a.status='ACTIVE'
 AND p_event.event_type IN ('BOOKING_REQUESTED','BOOKING_SCHEDULED','BOOKING_REJECTED','BOOKING_CANCELLED');
$$;

CREATE FUNCTION public.svc_expand_notification() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE e private.notification_events; r record; d uuid; a public.academies; s public.sessions; n integer:=0;
BEGIN
 SELECT * INTO e FROM private.notification_events WHERE status='QUEUED' AND booking_id IS NOT NULL
 AND coalesce(next_attempt_at,clock_timestamp())<=clock_timestamp() ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO a FROM public.academies WHERE id=e.academy_id;
 SELECT ss.* INTO s FROM public.sessions ss JOIN public.bookings b ON b.academy_id=ss.academy_id AND b.session_id=ss.id WHERE b.id=e.booking_id;
 IF a.status<>'ACTIVE' OR a.deleted_at IS NOT NULL THEN
 UPDATE private.notification_events SET status='FAILED',last_error_code='ACADEMY_UNAVAILABLE' WHERE id=e.id;
 RETURN jsonb_build_object('outcome','FAILED'); END IF;
 FOR r IN SELECT email,min(language) AS language FROM private.notification_recipients(e) GROUP BY email LOOP
 INSERT INTO private.notification_deliveries(scope,academy_id,event_id,recipient_email,template,language,status,provider,next_attempt_at,expires_at)
 VALUES('TENANT',e.academy_id,e.id,r.email,e.event_type,r.language,'QUEUED','BREVO',clock_timestamp(),
 CASE WHEN e.event_type='BOOKING_REMINDER' THEN s.starts_at ELSE clock_timestamp()+interval '1 day' END)
 ON CONFLICT(event_id,recipient_email) DO NOTHING RETURNING id INTO d;
 IF d IS NOT NULL THEN
 INSERT INTO private.notification_payloads(scope,academy_id,delivery_id,body,purge_at)
 VALUES('TENANT',e.academy_id,d,jsonb_build_object('event',e.event_type,'academy',a.name,'starts_at',s.starts_at,'timezone',a.timezone),
 clock_timestamp()+interval '1 day'); n:=n+1; END IF;
 END LOOP;
 UPDATE private.notification_events SET status=CASE WHEN n>0 THEN 'EXPANDED' ELSE 'FAILED' END,
 expanded_at=CASE WHEN n>0 THEN clock_timestamp() END,last_error_code=CASE WHEN n=0 THEN 'ROUTING_UNRESOLVED' END WHERE id=e.id;
 RETURN jsonb_build_object('outcome',CASE WHEN n>0 THEN 'EXPANDED' ELSE 'FAILED' END,'deliveries',n);
END;
$$;

CREATE FUNCTION public.svc_queue_reminders() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE r private.booking_reminders; b public.bookings; s public.sessions; ctx jsonb; ev uuid; n integer:=0;
BEGIN
 FOR r IN SELECT * FROM private.booking_reminders WHERE status='SCHEDULED' AND due_at<=clock_timestamp()
 ORDER BY due_at FOR UPDATE SKIP LOCKED LIMIT 100 LOOP
 SELECT * INTO b FROM public.bookings WHERE academy_id=r.academy_id AND id=r.booking_id;
 SELECT * INTO s FROM public.sessions WHERE academy_id=b.academy_id AND id=b.session_id;
 IF b.status<>'CONFIRMED' OR b.deleted_at IS NOT NULL OR b.revision<>r.booking_revision OR s.starts_at<>r.starts_at
 OR s.starts_at<=clock_timestamp() OR s.status<>'OPEN' THEN
 UPDATE private.booking_reminders SET status='SKIPPED',reason_code='STALE_BOOKING' WHERE booking_id=r.booking_id;
 CONTINUE; END IF;
 ev:=gen_random_uuid(); ctx:=private.system_context(r.academy_id,'queue_reminder',ev,jsonb_build_array(r.booking_id,r.booking_revision));
 INSERT INTO private.notification_events(id,scope,academy_id,operation_id,effect_key,booking_id,event_type,snapshot,status,next_attempt_at)
 VALUES(ev,'TENANT',r.academy_id,(ctx->>'operation_id')::uuid,'notify',r.booking_id,'BOOKING_REMINDER',
 jsonb_build_object('revision',r.booking_revision,'starts_at',r.starts_at),'QUEUED',clock_timestamp());
 UPDATE private.booking_reminders SET status='QUEUED',event_id=ev WHERE booking_id=r.booking_id;
 PERFORM private.system_finish(ctx,jsonb_build_object('event_id',ev),'reminder.queued',r.booking_id); n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('queued',n);
END;
$$;

CREATE FUNCTION public.svc_claim_delivery() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d private.notification_deliveries; e private.notification_events; payload jsonb; token uuid:=gen_random_uuid(); v_until timestamptz;
BEGIN
 -- A lost sender may have sent: never automatically send this message again.
 UPDATE private.notification_deliveries SET status='UNKNOWN',uncertain_since=clock_timestamp(),retryable=false,last_error_code='LEASE_EXPIRED'
 WHERE status='SENDING' AND lease_until<clock_timestamp();
 SELECT * INTO d FROM private.notification_deliveries WHERE status IN ('QUEUED','RETRY')
 AND next_attempt_at<=clock_timestamp() AND attempts<10 ORDER BY next_attempt_at,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO e FROM private.notification_events WHERE id=d.event_id;
 SELECT body INTO payload FROM private.notification_payloads WHERE delivery_id=d.id AND purge_at>clock_timestamp();
 IF payload IS NULL OR d.expires_at<=clock_timestamp() OR NOT EXISTS(SELECT FROM public.academies WHERE id=d.academy_id AND status='ACTIVE' AND deleted_at IS NULL)
 OR (e.invitation_id IS NOT NULL AND NOT EXISTS(SELECT FROM private.academy_invitations i WHERE i.id=e.invitation_id
 AND i.status='SENT' AND i.expires_at>clock_timestamp() AND private.inviter_authorized(i)))
 OR (e.booking_id IS NOT NULL AND NOT EXISTS(SELECT FROM private.notification_recipients(e) x WHERE x.email=d.recipient_email))
 OR (e.event_type='BOOKING_REMINDER' AND NOT EXISTS(SELECT FROM public.bookings b JOIN public.sessions s ON s.academy_id=b.academy_id AND s.id=b.session_id
 WHERE b.id=e.booking_id AND b.status='CONFIRMED' AND b.deleted_at IS NULL AND b.revision=(e.snapshot->>'revision')::bigint
 AND s.starts_at=(e.snapshot->>'starts_at')::timestamptz AND s.starts_at>clock_timestamp() AND s.status='OPEN')) THEN
 UPDATE private.notification_deliveries SET status='SKIPPED',last_error_code='STALE_OR_EXPIRED' WHERE id=d.id;
 RETURN jsonb_build_object('skipped',true); END IF;
 -- One instant for both columns: the SENDING CHECK requires next_attempt_at = lease_until.
 v_until:=clock_timestamp()+interval '120 seconds';
 UPDATE private.notification_deliveries SET status='SENDING',attempts=attempts+1,lease_token=token,
 lease_until=v_until,next_attempt_at=v_until WHERE id=d.id;
 RETURN jsonb_build_object('id',d.id,'lease_token',token,'email',d.recipient_email,'language',d.language,
 'template',d.template,'idempotency_key',d.idempotency_key,'body',payload);
END;
$$;
CREATE FUNCTION public.svc_record_delivery(p_delivery uuid,p_lease uuid,p_outcome text,p_message_id text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d private.notification_deliveries;
BEGIN
 SELECT * INTO d FROM private.notification_deliveries WHERE id=p_delivery FOR UPDATE;
 IF NOT FOUND OR d.lease_token IS DISTINCT FROM p_lease THEN PERFORM private.fail('LEASE_LOST'); END IF;
 -- Webhook may already have advanced the state while HTTP was in flight.
 IF d.provider_event_at IS NOT NULL THEN RETURN jsonb_build_object('outcome',d.status); END IF;
 IF d.status NOT IN ('SENDING','UNKNOWN') THEN RETURN jsonb_build_object('outcome',d.status); END IF;
 IF p_outcome IS NULL OR p_outcome NOT IN ('ACCEPTED','RETRY','FAILED','UNKNOWN')
 OR (p_outcome='ACCEPTED' AND nullif(p_message_id,'') IS NULL) OR length(p_message_id)>500 THEN PERFORM private.fail('INVALID_INPUT','22023'); END IF;
 UPDATE private.notification_deliveries SET status=CASE WHEN p_outcome='RETRY' AND attempts>=10 THEN 'FAILED' ELSE p_outcome END,
 provider_message_id=p_message_id,accepted_at=CASE WHEN p_outcome='ACCEPTED' THEN clock_timestamp() END,
 uncertain_since=CASE WHEN p_outcome='UNKNOWN' THEN clock_timestamp() END,retryable=(p_outcome='RETRY'),
 next_attempt_at=CASE WHEN p_outcome='RETRY' THEN clock_timestamp()+make_interval(secs=>least(3600,30*(2^least(attempts,6))::integer)) END,
 last_error_code=CASE WHEN p_outcome<>'ACCEPTED' THEN 'PROVIDER_'||p_outcome END WHERE id=d.id;
 RETURN jsonb_build_object('outcome',p_outcome);
END;
$$;
CREATE FUNCTION public.svc_apply_email_webhook(p_delivery uuid,p_message_id text,p_event text,p_occurred_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d private.notification_deliveries; key text; new_status text;
BEGIN
 IF p_message_id IS NULL OR length(p_message_id)>500 OR p_occurred_at IS NULL OR p_occurred_at>clock_timestamp()+interval '5 minutes'
 THEN PERFORM private.fail('INVALID_INPUT','22023'); END IF;
 new_status:=CASE p_event WHEN 'delivered' THEN 'DELIVERED' WHEN 'deferred' THEN 'DEFERRED' WHEN 'hard_bounce' THEN 'BOUNCED'
 WHEN 'soft_bounce' THEN 'DEFERRED' WHEN 'blocked' THEN 'BLOCKED' WHEN 'spam' THEN 'COMPLAINED' WHEN 'request' THEN 'ACCEPTED' END;
 IF new_status IS NULL THEN RETURN jsonb_build_object('outcome','IGNORED'); END IF;
 SELECT * INTO d FROM private.notification_deliveries WHERE id=p_delivery FOR UPDATE;
 IF NOT FOUND OR d.attempts=0 OR (d.provider_message_id IS NOT NULL AND d.provider_message_id<>p_message_id)
 OR p_occurred_at<d.created_at-interval '5 minutes' THEN PERFORM private.fail('CORRELATION_FAILED','22023'); END IF;
 key:=encode(sha256(convert_to(jsonb_build_array(p_delivery,p_message_id,p_event,p_occurred_at)::text,'UTF8')),'hex');
 INSERT INTO private.notification_webhook_receipts(scope,academy_id,receipt_key,delivery_id,provider_event,provider_message_id,provider_occurred_at,purge_at)
 VALUES(d.scope,d.academy_id,key,d.id,p_event,p_message_id,p_occurred_at,clock_timestamp()+interval '30 days') ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN jsonb_build_object('outcome','DUPLICATE'); END IF;
 IF (d.provider_event_at IS NULL OR p_occurred_at>d.provider_event_at)
 AND (d.status NOT IN ('DELIVERED','BOUNCED','BLOCKED','COMPLAINED') OR new_status='COMPLAINED') THEN
 UPDATE private.notification_deliveries SET status=new_status,provider_message_id=p_message_id,provider_event_at=p_occurred_at,
 delivered_at=CASE WHEN new_status='DELIVERED' THEN p_occurred_at ELSE delivered_at END,retryable=false WHERE id=d.id;
 END IF;
 RETURN jsonb_build_object('outcome','APPLIED');
END;
$$;
CREATE FUNCTION public.retry_notification(p_academy uuid,p_delivery uuid,p_reason text,p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE ctx jsonb; d private.notification_deliveries;
BEGIN
 PERFORM private.require_permission(p_academy,'notifications.retry');
 ctx:=private.cmd_begin(p_academy,'retry_notification',p_operation_key,jsonb_build_array(p_delivery,p_reason));
 IF ctx ? 'replay' THEN RETURN ctx->'replay'; END IF;
 PERFORM private.reason(p_reason,true);
 SELECT * INTO d FROM private.notification_deliveries WHERE academy_id=p_academy AND id=p_delivery FOR UPDATE;
 IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND','P0002'); END IF;
 IF d.status='UNKNOWN' THEN PERFORM private.fail('DELIVERY_UNCERTAIN'); END IF;
 IF d.status<>'FAILED' OR NOT d.retryable THEN PERFORM private.fail('NOT_RETRYABLE'); END IF;
 IF NOT EXISTS(SELECT FROM private.notification_payloads WHERE delivery_id=d.id AND purge_at>clock_timestamp())
 THEN PERFORM private.fail('PAYLOAD_EXPIRED'); END IF;
 UPDATE private.notification_deliveries SET status='RETRY',attempts=0,next_attempt_at=clock_timestamp() WHERE id=d.id;
 PERFORM private.audit(ctx,'audit','notification.retry_requested','delivery',d.id,p_reason);
 RETURN private.cmd_finish(ctx,jsonb_build_object('outcome','RETRY'));
END;
$$;
CREATE FUNCTION public.svc_purge_notification_content() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE n integer;
BEGIN
 DELETE FROM private.notification_payloads WHERE delivery_id IN (SELECT delivery_id FROM private.notification_payloads
 WHERE purge_at<=clock_timestamp() ORDER BY purge_at LIMIT 100 FOR UPDATE SKIP LOCKED);
 GET DIAGNOSTICS n=ROW_COUNT;
 -- Delivery, webhook receipt and audit history remain until D28 retention is approved.
 RETURN jsonb_build_object('purged',n);
END;
$$;
REVOKE ALL ON FUNCTION private.notification_recipients(private.notification_events) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.set_notification_recipients(uuid,jsonb,uuid),public.retry_notification(uuid,uuid,text,uuid),
 public.svc_expand_notification(),public.svc_queue_reminders(),public.svc_claim_delivery(),public.svc_record_delivery(uuid,uuid,text,text),
 public.svc_apply_email_webhook(uuid,text,text,timestamptz),public.svc_purge_notification_content() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_notification_recipients(uuid,jsonb,uuid),public.retry_notification(uuid,uuid,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_expand_notification(),public.svc_queue_reminders(),public.svc_claim_delivery(),
 public.svc_record_delivery(uuid,uuid,text,text),public.svc_apply_email_webhook(uuid,text,text,timestamptz),public.svc_purge_notification_content() TO service_role;
