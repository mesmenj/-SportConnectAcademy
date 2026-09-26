-- 3D: Auth remains the only authority for email and verification. No public signup.
ALTER TABLE private.academy_invitations ADD COLUMN lease_token uuid,
  ADD COLUMN lease_until timestamptz, ADD COLUMN attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0);

CREATE FUNCTION private.actor_permission(p_user uuid, p_academy uuid, p_permission text) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
 SELECT EXISTS (SELECT FROM public.user_profiles u JOIN public.academy_memberships m ON m.user_id=u.id
 JOIN public.academies a ON a.id=m.academy_id
 JOIN private.academy_membership_roles r ON r.academy_id=m.academy_id AND r.membership_id=m.id
 JOIN private.academy_role_permissions rp ON rp.role_code=r.role_code
 WHERE u.id=p_user AND u.status='ACTIVE' AND m.status='ACTIVE' AND a.status='ACTIVE' AND a.deleted_at IS NULL
 AND a.id=p_academy AND r.revoked_at IS NULL AND rp.permission_code=p_permission);
$$;
CREATE FUNCTION private.inviter_authorized(p_invitation private.academy_invitations) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
 SELECT (private.actor_permission(p_invitation.requested_by,p_invitation.academy_id,'memberships.invite')
 AND (NOT 'ACADEMY_OWNER'=ANY(p_invitation.requested_role_codes)
 OR private.actor_permission(p_invitation.requested_by,p_invitation.academy_id,'memberships.transfer_owner')))
 OR (p_invitation.requested_role_codes=ARRAY['ACADEMY_OWNER']::text[]
 AND NOT EXISTS(SELECT FROM public.academy_memberships WHERE academy_id=p_invitation.academy_id)
 AND EXISTS(SELECT FROM private.platform_user_roles r JOIN private.platform_role_permissions rp ON rp.role_code=r.role_code
 JOIN public.user_profiles u ON u.id=r.user_id WHERE r.user_id=p_invitation.requested_by AND u.status='ACTIVE'
 AND r.revoked_at IS NULL AND rp.permission_code='academies.create'));
$$;

-- No profile trigger: acceptance creates a minimal profile without trusting role metadata.
CREATE FUNCTION public.accept_invitation(p_invitation uuid, p_token text, p_display_name text,
 p_language text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE i private.academy_invitations; a public.academies; m public.academy_memberships;
 v_user uuid:=auth.uid(); v_email text; ctx jsonb; v_academy uuid;
BEGIN
 IF v_user IS NULL THEN PERFORM private.fail('FORBIDDEN','42501'); END IF;
 SELECT lower(email) INTO v_email FROM auth.users WHERE id=v_user AND email_confirmed_at IS NOT NULL;
 IF v_email IS NULL THEN PERFORM private.fail('VERIFIED_EMAIL_REQUIRED','42501'); END IF;
 SELECT academy_id INTO v_academy FROM private.academy_invitations WHERE id=p_invitation;
 a:=private.lock_academy(v_academy);
 SELECT * INTO i FROM private.academy_invitations WHERE id=p_invitation FOR UPDATE;
 IF NOT FOUND OR i.email<>v_email OR p_token IS NULL OR length(p_token)<>64
 OR i.token_digest IS DISTINCT FROM encode(sha256(convert_to(p_token,'UTF8')),'hex') THEN
   PERFORM private.fail('INVITATION_UNAVAILABLE','42501'); END IF;
 IF a.status<>'ACTIVE' OR a.deleted_at IS NOT NULL THEN PERFORM private.fail('FORBIDDEN','42501'); END IF;
 IF p_language IS NULL OR p_language NOT IN ('FR','EN') THEN PERFORM private.fail('INVALID_INPUT','22023'); END IF;
 PERFORM private.require_text(p_display_name,160);
 IF EXISTS(SELECT FROM public.user_profiles WHERE id=v_user AND status<>'ACTIVE') THEN PERFORM private.fail('FORBIDDEN','42501'); END IF;
 IF i.status<>'ACCEPTED' AND (i.status<>'SENT' OR i.expires_at<=clock_timestamp()) THEN PERFORM private.fail('INVITATION_UNAVAILABLE','42501'); END IF;
 IF i.status<>'ACCEPTED' AND NOT private.inviter_authorized(i) THEN PERFORM private.fail('INVITER_REVOKED','42501'); END IF;
 INSERT INTO public.user_profiles(id,display_name,preferred_language,status)
 VALUES(v_user,btrim(p_display_name),p_language,'ACTIVE') ON CONFLICT(id) DO NOTHING;
 ctx:=private.cmd_begin(NULL,'accept_invitation',p_operation_key,
 jsonb_build_object('invitation',p_invitation,'token_digest',i.token_digest,'display_name',p_display_name,'language',p_language),true);
 -- cmd_begin's hash includes the invitation; tenant scope is bound before effects.
 ctx:=ctx||jsonb_build_object('academy_id',i.academy_id);
 IF ctx ? 'replay' THEN
   PERFORM private.require_permission(i.academy_id,'academy.read');
   RETURN ctx->'replay';
 END IF;
 IF i.status='ACCEPTED' THEN PERFORM private.fail('INVITATION_ALREADY_ACCEPTED'); END IF;
 PERFORM private.validate_roles(i.requested_role_codes);
 SELECT * INTO m FROM public.academy_memberships WHERE academy_id=i.academy_id AND user_id=v_user FOR UPDATE;
 IF FOUND AND m.status='SUSPENDED' THEN PERFORM private.fail('MEMBERSHIP_SUSPENDED','42501'); END IF;
 IF m.id IS NULL THEN
   INSERT INTO public.academy_memberships(academy_id,user_id,status,joined_at,created_by)
   VALUES(i.academy_id,v_user,'ACTIVE',clock_timestamp(),v_user) RETURNING * INTO m;
 ELSE
   UPDATE public.academy_memberships SET status='ACTIVE',joined_at=coalesce(joined_at,clock_timestamp()) WHERE id=m.id;
 END IF;
 INSERT INTO private.academy_membership_roles(academy_id,membership_id,role_code,granted_by)
 SELECT i.academy_id,m.id,r,i.requested_by FROM unnest(i.requested_role_codes) r
 ON CONFLICT(membership_id,role_code) WHERE revoked_at IS NULL DO NOTHING;
 IF 'COACH'=ANY(i.requested_role_codes) THEN
   INSERT INTO public.coaches(academy_id,membership_id,created_by) VALUES(i.academy_id,m.id,v_user)
   ON CONFLICT(membership_id) DO NOTHING;
 END IF;
 UPDATE private.academy_invitations SET status='ACCEPTED',accepted_at=clock_timestamp(),invited_user_id=v_user,
 membership_id=m.id,lease_token=NULL,lease_until=NULL WHERE id=i.id;
 PERFORM private.audit(ctx,'audit','invitation.accepted','invitation',i.id);
 RETURN private.cmd_finish(ctx,jsonb_build_object('outcome','ACCEPTED','academy_id',i.academy_id,'membership_id',m.id));
END;
$$;

-- Service-only leases survive an Edge restart. Provisioning is not membership acceptance.
CREATE FUNCTION public.svc_claim_invitation() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE i private.academy_invitations; token uuid:=gen_random_uuid();
BEGIN
 UPDATE private.academy_invitations SET status='FAILED',last_error_code='PROVISIONING_EXHAUSTED'
 WHERE status='PROVISIONING' AND lease_until<clock_timestamp() AND attempts>=10;
 UPDATE private.academy_invitations SET status='EXPIRED',lease_token=NULL,lease_until=NULL
 WHERE status IN ('REQUESTED','PROVISIONING','SENT') AND expires_at<=clock_timestamp();
 SELECT * INTO i FROM private.academy_invitations
 WHERE (status='REQUESTED' OR (status='PROVISIONING' AND lease_until<clock_timestamp())) AND attempts<10
 ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF NOT private.inviter_authorized(i) OR NOT EXISTS(SELECT FROM public.academies WHERE id=i.academy_id AND status='ACTIVE' AND deleted_at IS NULL) THEN
 UPDATE private.academy_invitations SET status='FAILED',last_error_code='INVITER_REVOKED' WHERE id=i.id;
 RETURN NULL; END IF;
 UPDATE private.academy_invitations SET status='PROVISIONING',lease_token=token,
 lease_until=clock_timestamp()+interval '120 seconds',attempts=attempts+1 WHERE id=i.id;
 RETURN jsonb_build_object('id',i.id,'email',i.email,'lease_token',token,'expires_at',i.expires_at,
 'existing_user',EXISTS(SELECT FROM auth.users WHERE lower(email)=i.email));
END;
$$;

CREATE FUNCTION public.svc_finish_invitation(p_invitation uuid,p_lease uuid,p_user uuid,p_digest text,p_link text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE i private.academy_invitations; e private.notification_events; d uuid; a uuid;
BEGIN
 SELECT academy_id INTO a FROM private.academy_invitations WHERE id=p_invitation;
 PERFORM private.lock_academy(a);
 SELECT * INTO i FROM private.academy_invitations WHERE id=p_invitation FOR UPDATE;
 IF i.status IS DISTINCT FROM 'PROVISIONING' OR i.lease_token IS DISTINCT FROM p_lease OR i.lease_until<=clock_timestamp()
 OR i.expires_at<=clock_timestamp() THEN PERFORM private.fail('LEASE_LOST'); END IF;
 IF NOT private.inviter_authorized(i) OR NOT EXISTS(SELECT FROM public.academies WHERE id=i.academy_id AND status='ACTIVE' AND deleted_at IS NULL)
 THEN PERFORM private.fail('INVITER_REVOKED','42501'); END IF;
 IF p_digest IS NULL OR p_digest !~ '^[0-9a-f]{64}$' OR p_link IS NULL OR length(p_link)>4096
 OR NOT EXISTS(SELECT FROM auth.users WHERE id=p_user AND lower(email)=i.email) THEN PERFORM private.fail('INVALID_INPUT','22023'); END IF;
 -- Profile is created at acceptance, not from Auth metadata. invited_user_id FK is set then.
 UPDATE private.academy_invitations SET status='SENT',token_digest=p_digest,lease_token=NULL,lease_until=NULL WHERE id=i.id;
 SELECT * INTO e FROM private.notification_events WHERE invitation_id=i.id AND event_type IN ('MEMBERSHIP_INVITED','INVITATION_RESENT') AND status='QUEUED' ORDER BY created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN PERFORM private.fail('OUTBOX_MISSING'); END IF;
 INSERT INTO private.notification_deliveries(scope,academy_id,event_id,recipient_email,template,language,status,provider,next_attempt_at,expires_at)
 SELECT 'TENANT',i.academy_id,e.id,i.email,e.event_type,default_language,'QUEUED','BREVO',clock_timestamp(),
 least(i.expires_at,clock_timestamp()+interval '30 minutes') FROM public.academies WHERE id=i.academy_id
 RETURNING id INTO d;
 INSERT INTO private.notification_payloads(scope,academy_id,delivery_id,body,purge_at)
 VALUES('TENANT',i.academy_id,d,jsonb_build_object('invitation_url',p_link),least(i.expires_at,clock_timestamp()+interval '30 minutes'));
 UPDATE private.notification_events SET status='EXPANDED',expanded_at=clock_timestamp() WHERE id=e.id;
 RETURN jsonb_build_object('outcome','QUEUED');
END;
$$;

REVOKE ALL ON FUNCTION private.actor_permission(uuid,uuid,text),private.inviter_authorized(private.academy_invitations) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.accept_invitation(uuid,text,text,text,uuid),public.svc_claim_invitation(),public.svc_finish_invitation(uuid,uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.accept_invitation(uuid,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_claim_invitation(),public.svc_finish_invitation(uuid,uuid,uuid,text,text) TO service_role;
