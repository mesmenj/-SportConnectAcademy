\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir support/helpers.sql
\ir support/fixtures.sql

CREATE FUNCTION pg_temp.receipt(n integer, academy integer DEFAULT 101, scope_name text DEFAULT 'TENANT') RETURNS void LANGUAGE sql AS $$
 INSERT INTO private.command_receipts (id,scope,academy_id,actor_kind,actor_user_id,actor_ref,rpc_name,operation_key,request_hash,result,completed_at)
 VALUES(pg_temp.id(n),scope_name,pg_temp.id(academy),'USER',pg_temp.id(1),pg_temp.id(1)::text,'test_command',pg_temp.id(n),repeat('a',64),'{}',now());
$$;
SELECT pg_temp.receipt(1201);
SELECT pg_temp.receipt(1202,102);
SELECT pg_temp.receipt(1203,NULL,'PLATFORM');
CREATE FUNCTION pg_temp.payment(n integer, academy integer, player integer, package integer, operation integer, value numeric DEFAULT 100, state text DEFAULT 'PENDING') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.academy_payments (id,academy_id,player_id,package_id,amount,currency,method,status,origin,confirmed_at,created_by,operation_id)
 VALUES(pg_temp.id(n),pg_temp.id(academy),pg_temp.id(player),pg_temp.id(package),value,'XAF','CASH',state,'ADMIN_DECLARATION',CASE WHEN state='CONFIRMED' THEN now() END,pg_temp.id(1),pg_temp.id(operation));
$$;
CREATE FUNCTION pg_temp.event(n integer, academy integer, scope_name text, operation integer) RETURNS void LANGUAGE sql AS $$
 INSERT INTO private.notification_events (id,scope,academy_id,operation_id,effect_key,event_type,snapshot,status)
 VALUES(pg_temp.id(n),scope_name,pg_temp.id(academy),pg_temp.id(operation),'notification:' || n,'MEMBERSHIP_INVITED','{}','QUEUED');
$$;
CREATE FUNCTION pg_temp.delivery(n integer, academy integer, scope_name text, event_no integer) RETURNS void LANGUAGE sql AS $$
 INSERT INTO private.notification_deliveries (id,scope,academy_id,event_id,recipient_email,template,language,status,provider)
 VALUES(pg_temp.id(n),scope_name,pg_temp.id(academy),pg_temp.id(event_no),'synthetic-' || n || '@example.test','invitation','FR','QUEUED','BREVO');
$$;

-- Prove effects can precede their receipt inside one transaction.
SELECT pg_temp.payment(1301,101,301,801,1210);
SELECT pg_temp.receipt(1210);
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ok(EXISTS(SELECT FROM public.academy_payments WHERE id=pg_temp.id(1301)), 'effect inserted before receipt validates at transaction boundary');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1299)$q$,'23503','missing receipt rejected when constraints are checked');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1202)$q$,'23514','academy A effect cannot use academy B receipt');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1203)$q$,'23514','tenant effect cannot use platform receipt');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1210)$q$,'23505','payment operation cannot be applied twice');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,302,801,1201)$q$,'23503','payment must use package belonging to player');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,803,1201)$q$,'23503','payment cannot use package in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1201,100.25)$q$,'23514','fractional XAF payment rejected');
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1201,0)$q$,'23514','zero payment rejected');
UPDATE public.academy_payments SET status='CONFIRMED',confirmed_at=now() WHERE id=pg_temp.id(1301);
SELECT pg_temp.rejects($q$SELECT pg_temp.payment(1302,101,301,801,1201,100,'CONFIRMED')$q$,'23505','second confirmed payment for package rejected');
SELECT pg_temp.receipt(1211);
SELECT pg_temp.payment(1303,102,303,803,1202);
CREATE FUNCTION pg_temp.invoice(n integer, academy integer, player integer, payment integer, operation integer, value numeric DEFAULT 100) RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.academy_invoices (id,academy_id,player_id,payment_id,number,issued_at,amount,currency,status,source,payment_method,issuer_snapshot,customer_snapshot,operation_id)
 VALUES(pg_temp.id(n),pg_temp.id(academy),pg_temp.id(player),pg_temp.id(payment),'TEST-' || n,now(),value,'XAF','PAID','MANUAL','CASH','{}','{}',pg_temp.id(operation));
$$;
SELECT pg_temp.rejects($q$SELECT pg_temp.invoice(1401,101,302,1301,1211)$q$,'23503','invoice player must match payment player');
SELECT pg_temp.rejects($q$SELECT pg_temp.invoice(1401,101,NULL,1303,1211)$q$,'23503','invoice payment tenant checked even when player is NULL');
SELECT pg_temp.rejects($q$SELECT pg_temp.invoice(1401,101,301,1301,1211,100.25)$q$,'23514','fractional XAF invoice rejected');
SELECT pg_temp.invoice(1401,101,301,1301,1211);
SELECT pg_temp.ok(EXISTS(SELECT FROM public.academy_invoices WHERE id=pg_temp.id(1401)), 'valid invoice payment player chain accepted');
SELECT pg_temp.rejects($q$SELECT pg_temp.invoice(1402,101,301,1301,1201)$q$,'23505','one invoice per payment');

SELECT pg_temp.event(1501,101,'TENANT',1201);
SELECT pg_temp.event(1502,NULL,'PLATFORM',1203);
SELECT pg_temp.delivery(1601,101,'TENANT',1501);
SELECT pg_temp.delivery(1602,NULL,'PLATFORM',1502);
SELECT pg_temp.ok((SELECT count(*)=2 FROM private.notification_deliveries), 'matching tenant and platform deliveries accepted');
SELECT pg_temp.rejects($q$SELECT pg_temp.delivery(1603,NULL,'PLATFORM',1501)$q$,'23514','NULL academy cannot bypass event scope');
SELECT pg_temp.rejects($q$SELECT pg_temp.delivery(1603,102,'TENANT',1501)$q$,'23503','delivery in another academy rejected');
SELECT pg_temp.rejects($q$UPDATE private.notification_events SET scope='PLATFORM',academy_id=NULL WHERE id=pg_temp.id(1501)$q$,'23514','parent event scope immutable');
SELECT pg_temp.rejects($q$UPDATE private.notification_deliveries SET scope='PLATFORM',academy_id=NULL WHERE id=pg_temp.id(1601)$q$,'23514','child delivery scope immutable');
SELECT pg_temp.rejects($q$INSERT INTO private.notification_payloads (delivery_id,scope,body,purge_at) VALUES(pg_temp.id(1601),'PLATFORM','{}',now())$q$,'23514','payload cannot use NULL tenant to bypass delivery scope');
INSERT INTO private.notification_payloads (delivery_id,scope,academy_id,body,purge_at) VALUES(pg_temp.id(1601),'TENANT',pg_temp.id(101),'{}',now());
INSERT INTO private.notification_payloads (delivery_id,scope,body,purge_at) VALUES(pg_temp.id(1602),'PLATFORM','{}',now());
SELECT pg_temp.ok((SELECT count(*)=2 FROM private.notification_payloads), 'matching tenant and platform payloads accepted');
SELECT pg_temp.rejects($q$INSERT INTO private.notification_webhook_receipts (receipt_key,delivery_id,scope,provider_event,provider_message_id,purge_at) VALUES(repeat('b',64),pg_temp.id(1601),'PLATFORM','delivered','test-provider-id',now())$q$,'23514','webhook receipt scope checked with NULL tenant');
SELECT pg_temp.rejects($q$UPDATE private.notification_events SET status='PROCESSING',lease_token=gen_random_uuid(),lease_until=now(),next_attempt_at=NULL WHERE id=pg_temp.id(1501)$q$,'23514','processing lease requires recoverable deadline');
SELECT pg_temp.rejects($q$UPDATE private.notification_deliveries SET status='SENDING',lease_token=gen_random_uuid(),lease_until=now(),next_attempt_at=NULL WHERE id=pg_temp.id(1601)$q$,'23514','sending lease requires recoverable deadline');

INSERT INTO private.course_ledger (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,delta,reason,occurred_at)
VALUES(pg_temp.id(1701),pg_temp.id(101),pg_temp.id(1201),'purchase','SYSTEM','test',pg_temp.id(801),10,'PACKAGE_PURCHASE',now());
INSERT INTO private.course_ledger (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,booking_id,delta,reason,occurred_at)
VALUES(pg_temp.id(1702),pg_temp.id(101),pg_temp.id(1201),'consumption','SYSTEM','test',pg_temp.id(801),pg_temp.id(1001),-1,'SESSION_CONSUMED',now());
INSERT INTO private.course_ledger (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,booking_id,delta,reason,reverses_entry_id,occurred_at)
VALUES(pg_temp.id(1703),pg_temp.id(101),pg_temp.id(1201),'correction','SYSTEM','test',pg_temp.id(801),pg_temp.id(1001),1,'ATTENDANCE_CORRECTION',pg_temp.id(1702),now());
SELECT pg_temp.ok((SELECT sum(delta)=0 FROM private.course_ledger WHERE booking_id=pg_temp.id(1001)), 'consumption and precise compensation net to zero');
SELECT pg_temp.rejects($q$INSERT INTO private.course_ledger (academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,booking_id,delta,reason,reverses_entry_id,occurred_at) VALUES(pg_temp.id(101),pg_temp.id(1201),'second-correction','SYSTEM','test',pg_temp.id(801),pg_temp.id(1001),1,'ATTENDANCE_CORRECTION',pg_temp.id(1702),now())$q$,'23505','same debit cannot be compensated twice');
SELECT pg_temp.rejects($q$INSERT INTO private.course_ledger (academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,booking_id,delta,reason,occurred_at) VALUES(pg_temp.id(101),pg_temp.id(1201),'wrong-package','SYSTEM','test',pg_temp.id(802),pg_temp.id(1001),-1,'SESSION_CONSUMED',now())$q$,'23503','ledger booking must match package');
SELECT pg_temp.rejects($q$INSERT INTO private.course_ledger (academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,delta,reason,occurred_at) VALUES(pg_temp.id(101),pg_temp.id(1201),'zero','SYSTEM','test',pg_temp.id(801),0,'PACKAGE_PURCHASE',now())$q$,'23514','no zero or fictitious opening credit');
SELECT pg_temp.rejects($q$UPDATE private.course_ledger SET delta=20 WHERE id=pg_temp.id(1701)$q$,'23514','ledger update forbidden');
SELECT pg_temp.rejects($q$DELETE FROM private.course_ledger WHERE id=pg_temp.id(1703)$q$,'23514','ledger delete forbidden');
SELECT pg_temp.rejects($q$TRUNCATE private.course_ledger$q$,'23514','ledger truncate forbidden');
INSERT INTO private.booking_events (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,booking_id,event_type,after_status,occurred_at,booking_revision)
VALUES(pg_temp.id(1801),pg_temp.id(101),pg_temp.id(1201),'requested','SYSTEM','test',pg_temp.id(1001),'REQUESTED','PENDING',now(),1);
SELECT pg_temp.rejects($q$INSERT INTO private.booking_events (academy_id,operation_id,effect_key,actor_kind,actor_ref,booking_id,event_type,after_status,occurred_at,booking_revision) VALUES(pg_temp.id(101),pg_temp.id(1201),'override','SYSTEM','test',pg_temp.id(1001),'OVERRIDE_USED','PENDING',now(),1)$q$,'23514','override event requires reason');
SELECT pg_temp.rejects($q$UPDATE private.booking_events SET after_status='CONFIRMED' WHERE id=pg_temp.id(1801)$q$,'23514','booking history immutable');
INSERT INTO private.audit_log (id,scope,academy_id,operation_id,effect_key,actor_kind,actor_ref,action,resource_type,resource_id,occurred_at)
VALUES(pg_temp.id(1802),'TENANT',pg_temp.id(101),pg_temp.id(1201),'audit','SYSTEM','test','test','booking',pg_temp.id(1001),now());
SELECT pg_temp.rejects($q$DELETE FROM private.audit_log WHERE id=pg_temp.id(1802)$q$,'23514','audit delete forbidden');
SELECT pg_temp.rejects($q$UPDATE private.command_receipts SET result='{"forged":true}' WHERE id=pg_temp.id(1201)$q$,'23514','command result cannot be rewritten');
SELECT pg_temp.rejects($q$SELECT pg_temp.receipt(1201)$q$,'23505','operation replay cannot insert a duplicate receipt');

INSERT INTO public.platform_plans (id,code,version,name) VALUES(pg_temp.id(1901),'TEST',1,'Synthetic plan');
INSERT INTO public.academy_subscriptions (id,academy_id,plan_id,status,starts_at)
VALUES(pg_temp.id(1902),pg_temp.id(101),pg_temp.id(1901),'ACTIVE',now());
SELECT pg_temp.rejects($q$INSERT INTO public.academy_subscriptions (academy_id,plan_id,status,starts_at) VALUES(pg_temp.id(101),pg_temp.id(1901),'SUSPENDED',now())$q$,'23505','only one current subscription even if suspended');
INSERT INTO private.subscription_events (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,subscription_id,event_type,after_status,effective_at,reason)
VALUES(pg_temp.id(1903),pg_temp.id(101),pg_temp.id(1201),'subscription','SYSTEM','test',pg_temp.id(1902),'CREATED','ACTIVE',now(),'Test');
SELECT pg_temp.rejects($q$DELETE FROM private.subscription_events WHERE id=pg_temp.id(1903)$q$,'23514','subscription history immutable');

SELECT pg_temp.receipt(1220);
CREATE FUNCTION pg_temp.asset(n integer, academy integer, operation integer, path text) RETURNS void LANGUAGE sql AS $$
 INSERT INTO private.academy_assets (id,academy_id,usage,bucket_id,object_path,mime_type,byte_size,sha256,status,uploaded_by,operation_id)
 VALUES(pg_temp.id(n),pg_temp.id(academy),'BRANDING','academy-private-assets',path,'image/png',100,repeat('c',64),'PENDING',pg_temp.id(1),pg_temp.id(operation));
$$;
SELECT pg_temp.rejects($q$SELECT pg_temp.asset(2001,101,1220,'academies/other/branding/file.png')$q$,'23514','asset path bound to academy and asset UUID');
SELECT pg_temp.asset(2001,101,1220,'academies/' || pg_temp.id(101) || '/branding/' || pg_temp.id(2001) || '.png');
SELECT pg_temp.rejects($q$UPDATE public.academies SET logo_asset_id=pg_temp.id(2001) WHERE id=pg_temp.id(102)$q$,'23503','academy cannot reference another tenant logo');
SELECT pg_temp.rejects($q$UPDATE private.academy_assets SET bucket_id='public-assets' WHERE id=pg_temp.id(2001)$q$,'23514','only planned private asset bucket allowed');
SELECT pg_temp.rejects($q$UPDATE private.academy_assets SET byte_size=2000001 WHERE id=pg_temp.id(2001)$q$,'23514','asset size limit enforced');
SELECT pg_temp.rejects($q$UPDATE private.academy_assets SET status='READY' WHERE id=pg_temp.id(2001)$q$,'23514','asset cannot be READY without finalization timestamp');
SELECT pg_temp.rejects($q$UPDATE public.academies SET catalog_published=true WHERE id=pg_temp.id(101)$q$,'23514','no accidental public catalog');

SELECT '1..' || currval('pg_temp.assertion_number');
ROLLBACK;
