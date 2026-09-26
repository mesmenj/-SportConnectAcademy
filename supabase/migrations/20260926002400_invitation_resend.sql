-- Explicit resend revalidates access and invalidates the previous invitation token.
CREATE FUNCTION public.resend_invitation(p_academy uuid,p_invitation uuid,p_expires_at timestamptz,p_reason text,p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE ctx jsonb; i private.academy_invitations; platform_inviter boolean;
BEGIN
 PERFORM private.require_active_actor();
 PERFORM private.lock_academy(p_academy);
 SELECT * INTO i FROM private.academy_invitations WHERE academy_id=p_academy AND id=p_invitation FOR UPDATE;
 IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND','P0002'); END IF;
 platform_inviter:=i.requested_by=auth.uid() AND i.requested_role_codes=ARRAY['ACADEMY_OWNER']::text[]
 AND NOT EXISTS(SELECT FROM public.academy_memberships WHERE academy_id=p_academy)
 AND private.platform_permission('academies.create');
 IF NOT platform_inviter THEN
 PERFORM private.require_permission(p_academy,'memberships.invite');
 IF 'ACADEMY_OWNER'=ANY(i.requested_role_codes) THEN PERFORM private.require_permission(p_academy,'memberships.transfer_owner'); END IF;
 END IF;
 ctx:=private.cmd_begin(CASE WHEN platform_inviter THEN NULL ELSE p_academy END,'resend_invitation',p_operation_key,
 jsonb_build_array(p_academy,p_invitation,p_expires_at,p_reason),platform_inviter);
 IF ctx ? 'replay' THEN RETURN ctx->'replay'; END IF;
 ctx:=ctx||jsonb_build_object('academy_id',p_academy);
 IF i.status IN ('ACCEPTED','REVOKED') THEN PERFORM private.fail('INVALID_STATE'); END IF;
 PERFORM private.validate_invitation(i.email,p_expires_at);
 PERFORM private.reason(p_reason,true);
 -- A newer active invitation for this email supersedes the old link (academy row
 -- lock serializes this check with invite_member).
 IF EXISTS(SELECT FROM private.academy_invitations x WHERE x.academy_id=p_academy AND x.email=i.email AND x.id<>i.id
 AND x.status IN ('REQUESTED','PROVISIONING','SENT')) THEN PERFORM private.fail('INVITATION_EXISTS'); END IF;
 -- Do not race a provider send; an operator can resend after its lease settles.
 IF EXISTS(SELECT FROM private.notification_deliveries d JOIN private.notification_events e ON e.id=d.event_id
 WHERE e.invitation_id=i.id AND d.status='SENDING' AND d.lease_until>clock_timestamp()) THEN PERFORM private.fail('DELIVERY_IN_PROGRESS'); END IF;
 UPDATE private.academy_invitations SET status='REQUESTED',token_digest=NULL,lease_token=NULL,lease_until=NULL,
 expires_at=p_expires_at,last_requested_at=clock_timestamp(),attempts=0,last_error_code=NULL,requested_by=auth.uid() WHERE id=i.id;
 UPDATE private.notification_deliveries d SET status='SKIPPED',retryable=false,last_error_code='INVITATION_SUPERSEDED'
 FROM private.notification_events e WHERE e.id=d.event_id AND e.invitation_id=i.id AND d.status IN ('QUEUED','RETRY');
 UPDATE private.notification_events SET status='FAILED',last_error_code='INVITATION_SUPERSEDED'
 WHERE invitation_id=i.id AND status='QUEUED';
 PERFORM private.enqueue(ctx,'notify','INVITATION_RESENT',NULL,i.id,jsonb_build_object('invitation_id',i.id));
 PERFORM private.audit(ctx,'audit','invitation.resent','invitation',i.id,p_reason);
 RETURN private.cmd_finish(ctx,jsonb_build_object('outcome','REQUESTED','invitation_id',i.id));
END;
$$;
REVOKE ALL ON FUNCTION public.resend_invitation(uuid,uuid,timestamptz,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resend_invitation(uuid,uuid,timestamptz,text,uuid) TO authenticated;
