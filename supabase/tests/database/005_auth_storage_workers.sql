\set ON_ERROR_STOP on
\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir support/helpers.sql
\ir support/security_helpers.sql
\ir support/security_fixtures.sql
SET CONSTRAINTS ALL DEFERRED;
UPDATE private.academy_invitations SET status='REVOKED';
UPDATE private.notification_deliveries SET status='SKIPPED';
SELECT pg_temp.session(904,101,701,401,501,601,'2030-01-02 10:00Z','2030-01-02 11:00Z');
UPDATE auth.users SET email='user'||right(id::text,2)::integer||'@example.test',email_confirmed_at=clock_timestamp();
CREATE TEMP TABLE result(value jsonb);
CREATE FUNCTION pg_temp.exec(u integer,q text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
 DELETE FROM pg_temp.result; INSERT INTO pg_temp.result VALUES(pg_temp.query_as(u,'SELECT public.'||q)); END; $$;
CREATE FUNCTION pg_temp.last() RETURNS jsonb LANGUAGE sql AS $$ SELECT value FROM pg_temp.result; $$;
CREATE TEMP TABLE vars(k text PRIMARY KEY,v text);
GRANT SELECT ON vars TO authenticated,service_role;
CREATE FUNCTION pg_temp.save(k text,v text) RETURNS void LANGUAGE sql AS $$ INSERT INTO pg_temp.vars VALUES(k,v) ON CONFLICT(k) DO UPDATE SET v=EXCLUDED.v; $$;
CREATE FUNCTION pg_temp.v(key text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM pg_temp.vars WHERE k=key; $$;
CREATE FUNCTION pg_temp.svc(q text) RETURNS void LANGUAGE plpgsql AS $$ DECLARE v jsonb; BEGIN
 SET LOCAL ROLE service_role;
 BEGIN EXECUTE 'SELECT public.'||q INTO v; EXCEPTION WHEN OTHERS THEN RESET ROLE; RAISE; END;
 RESET ROLE; DELETE FROM pg_temp.result; INSERT INTO pg_temp.result VALUES(v); END; $$;

SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
 AND p.proname LIKE 'svc_%' AND (has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE'))), 'service RPCs unavailable to clients');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
 AND p.proname LIKE 'svc_%' AND (NOT p.prosecdef OR NOT has_function_privilege('service_role',p.oid,'EXECUTE') OR p.proconfig::text NOT LIKE '%search_path=pg_catalog%')), 'workers have explicit service grants and pinned paths');
SELECT pg_temp.ok((SELECT NOT public AND file_size_limit=2000000 FROM storage.buckets WHERE id='academy-private-assets'),'private bucket with byte limit');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_policies WHERE schemaname='storage' AND tablename='objects'),'no direct client Storage policy');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT public.svc_claim_invitation()')$q$,'42501','owner cannot impersonate worker');

-- Invitation saga: verified Auth email, digest, no metadata roles or prior membership.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(pg_temp.id(50),'new@example.test',NULL),(pg_temp.id(51),'wrong@example.test',clock_timestamp());
SELECT pg_temp.exec(10,$q$invite_member(pg_temp.id(101),'new@example.test',ARRAY['COACH'],clock_timestamp()+interval '1 day',pg_temp.id(5000))$q$);
SELECT pg_temp.save('invite',pg_temp.last()->>'invitation_id');
SELECT pg_temp.svc('svc_claim_invitation()');
SELECT pg_temp.save('lease',pg_temp.last()->>'lease_token');
SELECT pg_temp.ok(pg_temp.last()->>'id'=pg_temp.v('invite'),'worker claims durable invitation');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.academy_memberships WHERE user_id=pg_temp.id(50)),'provisioning gives no membership');
SELECT pg_temp.rejects($q$SELECT public.svc_finish_invitation(pg_temp.v('invite')::uuid,gen_random_uuid(),pg_temp.id(50),repeat('a',64),'https://example.test/#secret')$q$,'P0001','wrong lease cannot finish provisioning');
SELECT pg_temp.svc($q$svc_finish_invitation(pg_temp.v('invite')::uuid,pg_temp.v('lease')::uuid,pg_temp.id(50),encode(sha256(convert_to(repeat('b',64),'UTF8')),'hex'),'https://example.test/#secret')$q$);
SELECT pg_temp.ok((SELECT status='SENT' FROM private.academy_invitations WHERE id=pg_temp.v('invite')::uuid),'invitation queued with digest');
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.notification_payloads WHERE body ? 'invitation_url'),'sensitive invitation URL isolated in private payload');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(50,$rpc$accept_invitation(pg_temp.v('invite')::uuid,repeat('b',64),'New','FR',pg_temp.id(5001))$rpc$)$q$,'42501','unverified Auth email refused');
UPDATE auth.users SET email_confirmed_at=clock_timestamp() WHERE id=pg_temp.id(50);
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(51,$rpc$accept_invitation(pg_temp.v('invite')::uuid,repeat('b',64),'New','FR',pg_temp.id(5001))$rpc$)$q$,'42501','wrong recipient refused');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(50,$rpc$accept_invitation(pg_temp.v('invite')::uuid,repeat('c',64),'New','FR',pg_temp.id(5001))$rpc$)$q$,'42501','forged digest refused');
SELECT pg_temp.exec(50,$q$accept_invitation(pg_temp.v('invite')::uuid,repeat('b',64),'New','FR',pg_temp.id(5001))$q$);
SELECT pg_temp.save('membership',pg_temp.last()->>'membership_id');
SELECT pg_temp.ok(pg_temp.last()->>'outcome'='ACCEPTED' AND EXISTS(SELECT FROM public.coaches WHERE membership_id=pg_temp.v('membership')::uuid),'acceptance creates coach membership atomically');
SELECT pg_temp.exec(50,$q$accept_invitation(pg_temp.v('invite')::uuid,repeat('b',64),'New','FR',pg_temp.id(5001))$q$);
SELECT pg_temp.ok(pg_temp.last()->>'membership_id'=pg_temp.v('membership') AND (SELECT count(*)=1 FROM public.academy_memberships WHERE user_id=pg_temp.id(50)),'acceptance replay creates no duplicate');
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.academy_membership_roles WHERE membership_id=pg_temp.v('membership')::uuid AND role_code='COACH'),'only invited role assigned');
SELECT pg_temp.exec(10,$q$suspend_membership(pg_temp.id(101),pg_temp.v('membership')::uuid,'Test',pg_temp.id(5002))$q$);
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(50,$rpc$accept_invitation(pg_temp.v('invite')::uuid,repeat('b',64),'New','FR',pg_temp.id(5001))$rpc$)$q$,'42501','suspended member cannot replay acceptance');

-- New academy's first owner can onboard without an existing membership.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(pg_temp.id(52),'owner@example.test',clock_timestamp());
SELECT pg_temp.exec(15,$q$create_academy('New','Douala','CM','Africa/Douala','FR','owner@example.test',clock_timestamp()+interval '1 day',pg_temp.id(5003))$q$);
SELECT pg_temp.save('academy',pg_temp.last()->>'academy_id');
SELECT pg_temp.svc('svc_claim_invitation()');
SELECT pg_temp.save('owner_invite',pg_temp.last()->>'id'); SELECT pg_temp.save('owner_lease',pg_temp.last()->>'lease_token');
SELECT pg_temp.svc($q$svc_finish_invitation(pg_temp.v('owner_invite')::uuid,pg_temp.v('owner_lease')::uuid,pg_temp.id(52),encode(sha256(convert_to(repeat('d',64),'UTF8')),'hex'),'https://example.test/#owner')$q$);
SELECT pg_temp.exec(52,$q$accept_invitation(pg_temp.v('owner_invite')::uuid,repeat('d',64),'Owner','FR',pg_temp.id(5004))$q$);
SELECT pg_temp.ok(EXISTS(SELECT FROM private.academy_membership_roles WHERE academy_id=pg_temp.v('academy')::uuid AND role_code='ACADEMY_OWNER'),'first owner onboarding succeeds');
SELECT pg_temp.ok((SELECT count(*)=2 FROM private.audit_log WHERE action='invitation.accepted'),'acceptances audited');

-- Asset evidence and pointer switching are separate from HTTP upload.
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(13,$rpc$prepare_asset(pg_temp.id(101),'BRANDING',NULL,'image/png',100,repeat('a',64),pg_temp.id(5010))$rpc$)$q$,'42501','staff cannot upload branding');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(10,$rpc$prepare_asset(pg_temp.id(102),'BRANDING',NULL,'image/png',100,repeat('a',64),pg_temp.id(5010))$rpc$)$q$,'42501','cross-academy upload refused');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(10,$rpc$prepare_asset(pg_temp.id(101),'BRANDING',NULL,'image/svg+xml',100,repeat('a',64),pg_temp.id(5010))$rpc$)$q$,'22023','SVG rejected');
SELECT pg_temp.exec(10,$q$prepare_asset(pg_temp.id(101),'BRANDING',NULL,'image/png',100,repeat('a',64),pg_temp.id(5010))$q$);
SELECT pg_temp.save('asset',pg_temp.last()->>'asset_id');
SELECT pg_temp.ok((SELECT logo_asset_id IS NULL FROM public.academies WHERE id=pg_temp.id(101)),'preparation does not replace active logo');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(10,$rpc$authorize_asset_read(pg_temp.id(101),pg_temp.v('asset')::uuid)$rpc$)$q$,'P0002','pending asset cannot be signed');
SELECT pg_temp.rejects($q$SELECT public.svc_finalize_asset(pg_temp.v('asset')::uuid,pg_temp.id(10),'image/png',100,repeat('b',64))$q$,'22023','stored checksum mismatch rejected');
SELECT pg_temp.rejects($q$SELECT public.svc_finalize_asset(pg_temp.v('asset')::uuid,pg_temp.id(11),'image/png',100,repeat('a',64))$q$,'42501','other uploader cannot finalize');
SELECT pg_temp.svc($q$svc_finalize_asset(pg_temp.v('asset')::uuid,pg_temp.id(10),'image/png',100,repeat('a',64))$q$);
SELECT pg_temp.ok((SELECT logo_asset_id=pg_temp.v('asset')::uuid FROM public.academies WHERE id=pg_temp.id(101)),'validated asset becomes current logo');
SELECT pg_temp.exec(3,$q$authorize_asset_read(pg_temp.id(101),pg_temp.v('asset')::uuid)$q$);
SELECT pg_temp.ok(pg_temp.last()->>'bucket'='academy-private-assets','tenant member can authorize private logo read');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(8,$rpc$authorize_asset_read(pg_temp.id(101),pg_temp.v('asset')::uuid)$rpc$)$q$,'42501','other academy cannot sign asset');
SELECT pg_temp.svc($q$svc_finalize_asset(pg_temp.v('asset')::uuid,pg_temp.id(10),'image/png',100,repeat('a',64))$q$);
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.audit_log WHERE action='asset.finalized'),'finalization retry audited once');
SELECT pg_temp.rejects($q$SELECT public.svc_finish_asset_cleanup(pg_temp.v('asset')::uuid)$q$,'P0001','referenced asset protected from cleanup');

-- Outbox, exact recipient scope, uncertain send, webhook ordering.
SELECT pg_temp.exec(10,$q$set_notification_recipients(pg_temp.id(101),'[{"email":"ops@example.test","name":"Ops"}]',pg_temp.id(5020))$q$);
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.academy_notification_recipients WHERE academy_id=pg_temp.id(101) AND active),'local notification recipient configured');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(12,$rpc$set_notification_recipients(pg_temp.id(101),'[]',pg_temp.id(5021))$rpc$)$q$,'42501','manager cannot change routing');
SELECT pg_temp.exec(3,$q$request_booking(pg_temp.id(101),pg_temp.id(904),pg_temp.id(301),pg_temp.id(801),pg_temp.id(5022))$q$);
SELECT pg_temp.save('booking',pg_temp.last()->>'booking_id');
SELECT pg_temp.svc('svc_expand_notification()');
SELECT pg_temp.ok(pg_temp.last()->>'outcome'='EXPANDED','booking outbox expanded');
SELECT pg_temp.ok(EXISTS(SELECT FROM private.notification_deliveries d JOIN private.notification_events e ON e.id=d.event_id WHERE e.booking_id=pg_temp.v('booking')::uuid AND d.recipient_email='user3@example.test'),'linked booking owner routed');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM private.notification_deliveries d JOIN private.notification_events e ON e.id=d.event_id WHERE e.booking_id=pg_temp.v('booking')::uuid AND d.recipient_email='user8@example.test'),'no other-academy fallback');
SELECT pg_temp.svc('svc_claim_delivery()');
SELECT pg_temp.ok(pg_temp.last()->>'skipped'='true','accepted invitation email is skipped before sending');
SELECT pg_temp.svc('svc_claim_delivery()');
SELECT pg_temp.ok(pg_temp.last()->>'skipped'='true','onboarded owner email is skipped');
SELECT pg_temp.svc('svc_claim_delivery()');
SELECT pg_temp.save('delivery',pg_temp.last()->>'id'); SELECT pg_temp.save('delivery_lease',pg_temp.last()->>'lease_token');
SELECT pg_temp.ok(pg_temp.v('delivery') IS NOT NULL,'delivery claimed with lease');
SELECT pg_temp.rejects($q$SELECT public.svc_record_delivery(pg_temp.v('delivery')::uuid,gen_random_uuid(),'ACCEPTED','msg1')$q$,'P0001','stale sender rejected');
SELECT pg_temp.svc($q$svc_record_delivery(pg_temp.v('delivery')::uuid,pg_temp.v('delivery_lease')::uuid,'UNKNOWN',NULL)$q$);
SELECT pg_temp.ok((SELECT status='UNKNOWN' AND NOT retryable FROM private.notification_deliveries WHERE id=pg_temp.v('delivery')::uuid),'uncertain send is not retryable');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(10,$rpc$retry_notification(pg_temp.id(101),pg_temp.v('delivery')::uuid,'retry',pg_temp.id(5023))$rpc$)$q$,'P0001','manual retry refuses UNKNOWN');
SELECT pg_temp.save('stamp',clock_timestamp()::text);
SELECT pg_temp.svc($q$svc_apply_email_webhook(pg_temp.v('delivery')::uuid,'msg1','delivered',pg_temp.v('stamp')::timestamptz)$q$);
SELECT pg_temp.ok((SELECT status='DELIVERED' FROM private.notification_deliveries WHERE id=pg_temp.v('delivery')::uuid),'webhook reconciles uncertain send');
SELECT pg_temp.svc($q$svc_apply_email_webhook(pg_temp.v('delivery')::uuid,'msg1','delivered',pg_temp.v('stamp')::timestamptz)$q$);
SELECT pg_temp.ok(pg_temp.last()->>'outcome'='DUPLICATE','duplicate webhook idempotent');
SELECT pg_temp.svc($q$svc_record_delivery(pg_temp.v('delivery')::uuid,pg_temp.v('delivery_lease')::uuid,'ACCEPTED','msg1')$q$);
SELECT pg_temp.ok((SELECT status='DELIVERED' FROM private.notification_deliveries WHERE id=pg_temp.v('delivery')::uuid),'late HTTP result cannot undo webhook');
SELECT pg_temp.svc($q$svc_apply_email_webhook(pg_temp.v('delivery')::uuid,'msg1','deferred',clock_timestamp())$q$);
SELECT pg_temp.ok((SELECT status='DELIVERED' FROM private.notification_deliveries WHERE id=pg_temp.v('delivery')::uuid),'terminal delivery does not regress');
SELECT pg_temp.rejects($q$SELECT public.svc_apply_email_webhook(pg_temp.v('delivery')::uuid,'wrong','delivered',clock_timestamp())$q$,'22023','provider message mismatch refused');
SELECT pg_temp.svc('svc_queue_reminders()');
SELECT pg_temp.ok((pg_temp.last()->>'queued')::integer=0,'pending bookings have no reminders');
-- Lease recovery, invitation resend and inviter revocation.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(pg_temp.id(53),'retry@example.test',clock_timestamp());
SELECT pg_temp.exec(11,$q$invite_member(pg_temp.id(101),'retry@example.test',ARRAY['PARENT'],clock_timestamp()+interval '1 day',pg_temp.id(5030))$q$);
SELECT pg_temp.save('retry_invite',pg_temp.last()->>'invitation_id');
SELECT pg_temp.svc('svc_claim_invitation()');
SELECT pg_temp.save('old_lease',pg_temp.last()->>'lease_token');
SELECT pg_temp.svc('svc_claim_invitation()');
SELECT pg_temp.ok(pg_temp.last() IS NULL,'second worker cannot claim a live invitation lease');
UPDATE private.academy_invitations SET lease_until=clock_timestamp()-interval '1 second' WHERE id=pg_temp.v('retry_invite')::uuid;
SELECT pg_temp.svc('svc_claim_invitation()');
SELECT pg_temp.save('retry_lease',pg_temp.last()->>'lease_token');
SELECT pg_temp.ok(pg_temp.v('retry_lease')<>pg_temp.v('old_lease'),'expired provisioning lease reclaimed with new token');
SELECT pg_temp.rejects($q$SELECT public.svc_finish_invitation(pg_temp.v('retry_invite')::uuid,pg_temp.v('old_lease')::uuid,pg_temp.id(53),repeat('a',64),'https://example.test/')$q$,'P0001','expired provisioning worker cannot finish');
SELECT pg_temp.svc($q$svc_finish_invitation(pg_temp.v('retry_invite')::uuid,pg_temp.v('retry_lease')::uuid,pg_temp.id(53),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),'https://example.test/#retry')$q$);
SELECT pg_temp.exec(10,$q$resend_invitation(pg_temp.id(101),pg_temp.v('retry_invite')::uuid,transaction_timestamp()+interval '2 days','Expired email link',pg_temp.id(5031))$q$);
SELECT pg_temp.ok((SELECT token_digest IS NULL AND status='REQUESTED' FROM private.academy_invitations WHERE id=pg_temp.v('retry_invite')::uuid),'resend invalidates previous secret');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(53,$rpc$accept_invitation(pg_temp.v('retry_invite')::uuid,repeat('a',64),'Retry','FR',pg_temp.id(5032))$rpc$)$q$,'42501','old invitation link rejected after resend');
SELECT pg_temp.exec(10,$q$resend_invitation(pg_temp.id(101),pg_temp.v('retry_invite')::uuid,transaction_timestamp()+interval '2 days','Expired email link',pg_temp.id(5031))$q$);
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.notification_events WHERE invitation_id=pg_temp.v('retry_invite')::uuid AND event_type='INVITATION_RESENT'),'resend replay does not duplicate outbox');
SELECT pg_temp.svc('svc_claim_invitation()'); SELECT pg_temp.save('retry_lease',pg_temp.last()->>'lease_token');
SELECT pg_temp.svc($q$svc_finish_invitation(pg_temp.v('retry_invite')::uuid,pg_temp.v('retry_lease')::uuid,pg_temp.id(53),encode(sha256(convert_to(repeat('9',64),'UTF8')),'hex'),'https://example.test/#new')$q$);
SELECT pg_temp.ok(EXISTS(SELECT FROM private.notification_deliveries d JOIN private.notification_events e ON e.id=d.event_id
 WHERE e.invitation_id=pg_temp.v('retry_invite')::uuid AND d.template='INVITATION_RESENT' AND d.status='QUEUED'),'resend uses its own delivery');
-- Remove inviter role after provisioning; active membership alone must not suffice.
UPDATE private.academy_membership_roles SET revoked_at=clock_timestamp() WHERE membership_id=pg_temp.id(210) AND role_code='ACADEMY_OWNER';
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(53,$rpc$accept_invitation(pg_temp.v('retry_invite')::uuid,repeat('9',64),'Retry','FR',pg_temp.id(5033))$rpc$)$q$,'42501','revoked inviter blocks acceptance');
UPDATE private.academy_membership_roles SET revoked_at=NULL WHERE membership_id=pg_temp.id(210) AND role_code='ACADEMY_OWNER';
SELECT pg_temp.exec(53,$q$accept_invitation(pg_temp.v('retry_invite')::uuid,repeat('9',64),'Retry','FR',pg_temp.id(5033))$q$);
SELECT pg_temp.ok(pg_temp.last()->>'outcome'='ACCEPTED','new invitation secret accepts after permission restored');
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(10,$rpc$resend_invitation(pg_temp.id(101),pg_temp.v('retry_invite')::uuid,clock_timestamp()+interval '1 day','Already accepted',pg_temp.id(5034))$rpc$)$q$,'P0001','accepted invitation cannot resend');
-- An expired link superseded by a newer active invitation for the same email is not revived.
SELECT pg_temp.exec(10,$q$invite_member(pg_temp.id(101),'dup@example.test',ARRAY['PARENT'],clock_timestamp()+interval '1 day',pg_temp.id(5040))$q$);
SELECT pg_temp.save('old_dup',pg_temp.last()->>'invitation_id');
UPDATE private.academy_invitations SET status='EXPIRED' WHERE id=pg_temp.v('old_dup')::uuid;
SELECT pg_temp.exec(10,$q$invite_member(pg_temp.id(101),'dup@example.test',ARRAY['PARENT'],clock_timestamp()+interval '1 day',pg_temp.id(5041))$q$);
SELECT pg_temp.rejects($q$SELECT pg_temp.exec(10,$rpc$resend_invitation(pg_temp.id(101),pg_temp.v('old_dup')::uuid,clock_timestamp()+interval '1 day','Old link',pg_temp.id(5042))$rpc$)$q$,'P0001','superseded expired invitation not revived (INVITATION_EXISTS)');

-- Worker failure leaves immutable audit/receipt history; only expired sensitive payload is purged.
UPDATE private.notification_deliveries SET status='SKIPPED' WHERE status IN ('QUEUED','RETRY');
UPDATE private.notification_payloads SET purge_at=clock_timestamp()-interval '1 second' WHERE delivery_id=pg_temp.id(1801);
SELECT pg_temp.svc('svc_purge_notification_content()');
SELECT pg_temp.ok((pg_temp.last()->>'purged')::integer=1 AND EXISTS(SELECT FROM private.notification_deliveries WHERE id=pg_temp.id(1801)),'payload purge retains delivery history');
-- A committed send without a result is uncertain, not queued for automatic replay.
UPDATE private.notification_deliveries SET status='SENDING',lease_token=gen_random_uuid(),lease_until=x.t,
 next_attempt_at=x.t,attempts=1 FROM (SELECT clock_timestamp()-interval '1 second' AS t) x WHERE id=pg_temp.id(1802);
SELECT pg_temp.svc('svc_claim_delivery()');
SELECT pg_temp.ok((SELECT status='UNKNOWN' AND NOT retryable FROM private.notification_deliveries WHERE id=pg_temp.id(1802)),'lost sender lease becomes UNKNOWN');

-- Due reminders are versioned, idempotent and rechecked after cancellation.
SELECT pg_temp.exec(13,$q$approve_booking(pg_temp.id(101),pg_temp.v('booking')::uuid,1,pg_temp.id(5040))$q$);
UPDATE private.notification_events SET status='EXPANDED' WHERE status='QUEUED';
UPDATE public.sessions SET starts_at=clock_timestamp()+interval '1 hour',ends_at=clock_timestamp()+interval '2 hours' WHERE id=pg_temp.id(904);
UPDATE private.booking_reminders SET starts_at=(SELECT starts_at FROM public.sessions WHERE id=pg_temp.id(904)),due_at=clock_timestamp()-interval '1 second'
 WHERE booking_id=pg_temp.v('booking')::uuid;
SELECT pg_temp.svc('svc_queue_reminders()');
SELECT pg_temp.ok((pg_temp.last()->>'queued')::integer=1,'due reminder queued');
SELECT pg_temp.svc('svc_queue_reminders()');
SELECT pg_temp.ok((pg_temp.last()->>'queued')::integer=0,'scheduler retry does not duplicate reminder');
SELECT pg_temp.svc('svc_expand_notification()');
SELECT pg_temp.ok((pg_temp.last()->>'deliveries')::integer=1,'reminder routes only to linked family owner');
SELECT pg_temp.exec(13,$q$cancel_booking(pg_temp.id(101),pg_temp.v('booking')::uuid,2,'Cancelled',pg_temp.id(5041))$q$);
SELECT pg_temp.svc('svc_claim_delivery()');
SELECT pg_temp.ok(pg_temp.last()->>'skipped'='true','cancelled booking reminder skipped before HTTP');

-- An orphan cannot race back to READY while its immutable file is being removed.
INSERT INTO private.academy_assets(id,academy_id,created_at,usage,bucket_id,object_path,mime_type,byte_size,sha256,status,uploaded_by,operation_id)
VALUES(pg_temp.id(5050),pg_temp.id(101),clock_timestamp()-interval '10 days','BRANDING','academy-private-assets',
 'academies/'||pg_temp.id(101)||'/branding/'||pg_temp.id(5050)||'.png','image/png',100,repeat('a',64),'PENDING',pg_temp.id(10),pg_temp.id(1605));
SELECT pg_temp.svc($q$svc_claim_asset_cleanup(clock_timestamp()-interval '2 days')$q$);
SELECT pg_temp.ok(pg_temp.last()->>'asset_id'=pg_temp.id(5050)::text,'old unreferenced upload becomes cleanup candidate');
SELECT pg_temp.rejects($q$SELECT public.svc_finalize_asset(pg_temp.id(5050),pg_temp.id(10),'image/png',100,repeat('a',64))$q$,'P0001','cleanup tombstone blocks concurrent finalization');
SELECT pg_temp.svc('svc_finish_asset_cleanup(pg_temp.id(5050))');
SELECT pg_temp.ok((SELECT status='DELETED' FROM private.academy_assets WHERE id=pg_temp.id(5050)),'successful Storage deletion finalized');
SELECT pg_temp.svc('svc_finish_asset_cleanup(pg_temp.id(5050))');
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.audit_log WHERE action='asset.deleted' AND resource_id=pg_temp.id(5050)),'cleanup retry audited once');

SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ok(true,'all 3D receipt scopes and foreign keys valid at commit');
SELECT '1..'||last_value FROM pg_temp.assertion_number;
ROLLBACK;
