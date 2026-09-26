\ir fixtures.sql
INSERT INTO auth.users (id) SELECT pg_temp.id(n) FROM unnest(ARRAY[10,11,12,13,15,16,17,18,19,20,21,22]) n;
INSERT INTO public.user_profiles (id,display_name,phone,preferred_language,status)
SELECT pg_temp.id(n),'Security test '||n,'PRIVATE-PHONE-'||n,'FR',CASE WHEN n=18 THEN 'SUSPENDED' ELSE 'ACTIVE' END
FROM unnest(ARRAY[10,11,12,13,15,16,17,18,19,20,21,22]) n;
UPDATE public.user_profiles SET phone='PRIVATE-FAMILY-PHONE' WHERE id=pg_temp.id(3);
INSERT INTO public.academy_memberships (id,academy_id,user_id,status)
SELECT pg_temp.id(200+n),pg_temp.id(101),pg_temp.id(n),CASE WHEN n=19 THEN 'SUSPENDED' WHEN n=20 THEN 'INVITED' ELSE 'ACTIVE' END
FROM unnest(ARRAY[10,11,12,13,18,19,20,21,22]) n;
INSERT INTO private.academy_membership_roles (academy_id,membership_id,role_code) VALUES
(pg_temp.id(101),pg_temp.id(201),'COACH'),
(pg_temp.id(101),pg_temp.id(202),'COACH'),
(pg_temp.id(101),pg_temp.id(203),'PARENT'),
(pg_temp.id(101),pg_temp.id(204),'PARENT'),
(pg_temp.id(101),pg_temp.id(206),'STUDENT'),
(pg_temp.id(102),pg_temp.id(205),'PARENT'),
(pg_temp.id(102),pg_temp.id(208),'ACADEMY_OWNER'),
(pg_temp.id(101),pg_temp.id(210),'ACADEMY_OWNER'),
(pg_temp.id(101),pg_temp.id(211),'ACADEMY_ADMIN'),
(pg_temp.id(101),pg_temp.id(212),'MANAGER'),
(pg_temp.id(101),pg_temp.id(213),'STAFF'),
(pg_temp.id(101),pg_temp.id(218),'ACADEMY_OWNER'),
(pg_temp.id(101),pg_temp.id(219),'ACADEMY_OWNER'),
(pg_temp.id(101),pg_temp.id(220),'PARENT'),
(pg_temp.id(101),pg_temp.id(221),'COACH');
INSERT INTO private.platform_user_roles (user_id,role_code) VALUES
(pg_temp.id(15),'PLATFORM_ADMIN'),(pg_temp.id(16),'SUPER_ADMIN');
INSERT INTO public.player_links (id,academy_id,player_id,user_id,relationship,is_primary,is_financial_contact) VALUES
(pg_temp.id(1101),pg_temp.id(101),pg_temp.id(301),pg_temp.id(3),'GUARDIAN',true,true),
(pg_temp.id(1102),pg_temp.id(101),pg_temp.id(301),pg_temp.id(4),'GUARDIAN',false,false),
(pg_temp.id(1103),pg_temp.id(101),pg_temp.id(301),pg_temp.id(6),'SELF',false,false),
(pg_temp.id(1104),pg_temp.id(102),pg_temp.id(303),pg_temp.id(1),'GUARDIAN',true,true),
(pg_temp.id(1105),pg_temp.id(101),pg_temp.id(302),pg_temp.id(13),'GUARDIAN',true,true);
UPDATE public.sessions SET coach_id=pg_temp.id(402) WHERE id=pg_temp.id(902);
UPDATE public.bookings SET status='CONFIRMED' WHERE id=pg_temp.id(1001);
SELECT pg_temp.booking(1002,101,902,301,801,'CONFIRMED');
SELECT pg_temp.booking(1003,101,902,302,802,'CONFIRMED');
SELECT pg_temp.booking(1004,102,903,303,803,'PENDING');
UPDATE public.bookings SET deleted_at=now() WHERE id=pg_temp.id(1002);
UPDATE public.bookings SET note='PRIVATE-NOTE',contract_snapshot='{"secret":"PRIVATE-CONTRACT"}';
UPDATE public.player_packages SET terms_snapshot='{"secret":"PRIVATE-TERMS"}';
INSERT INTO public.booking_attendance (booking_id,academy_id,attended,recorded_by,recorded_at) VALUES
(pg_temp.id(1001),pg_temp.id(101),true,pg_temp.id(1),now()),
(pg_temp.id(1002),pg_temp.id(101),false,pg_temp.id(2),now());
INSERT INTO public.player_evaluations (id,academy_id,booking_id,session_id,coach_id,technical,tactical,physical,behavior,comment,evaluated_at,recorded_by) VALUES
(pg_temp.id(1201),pg_temp.id(101),pg_temp.id(1001),pg_temp.id(901),pg_temp.id(401),4,4,4,4,'Own coach note',now(),pg_temp.id(1)),
(pg_temp.id(1202),pg_temp.id(101),pg_temp.id(1002),pg_temp.id(902),pg_temp.id(402),3,3,3,3,'OTHER-COACH-NOTE',now(),pg_temp.id(2));
INSERT INTO private.command_receipts (id,scope,academy_id,actor_kind,actor_ref,rpc_name,operation_key,request_hash,result,completed_at)
SELECT pg_temp.id(n),CASE WHEN n=1604 THEN 'PLATFORM' ELSE 'TENANT' END,
  CASE WHEN n=1604 THEN NULL WHEN n IN (1603,1606) THEN pg_temp.id(102) ELSE pg_temp.id(101) END,
  'SYSTEM','security-fixture','fixture',pg_temp.id(n),repeat('a',64),'{}',now()
FROM generate_series(1601,1606) n;
INSERT INTO public.academy_payments (id,academy_id,player_id,package_id,amount,currency,method,status,origin,operation_id) VALUES
(pg_temp.id(1301),pg_temp.id(101),pg_temp.id(301),pg_temp.id(801),100,'XAF','CASH','PENDING','ADMIN_DECLARATION',pg_temp.id(1601)),
(pg_temp.id(1302),pg_temp.id(101),pg_temp.id(302),pg_temp.id(802),200,'XAF','CASH','PENDING','ADMIN_DECLARATION',pg_temp.id(1602)),
(pg_temp.id(1303),pg_temp.id(102),pg_temp.id(303),pg_temp.id(803),300,'XAF','CASH','PENDING','ADMIN_DECLARATION',pg_temp.id(1603)),
(pg_temp.id(1304),pg_temp.id(101),NULL,NULL,400,'XAF','CASH','PENDING','ADMIN_DECLARATION',pg_temp.id(1605));
INSERT INTO public.academy_invoices (id,academy_id,player_id,payment_id,number,issued_at,amount,currency,status,source,payment_method,issuer_snapshot,customer_snapshot,operation_id)
SELECT pg_temp.id(1400+n),p.academy_id,p.player_id,p.id,'SECURITY-'||n,now(),p.amount,p.currency,'UNPAID','MANUAL','CASH',
  '{"name":"Test issuer"}','{"name":"Test family","private":"PRIVATE-INVOICE-SNAPSHOT"}',p.operation_id
FROM generate_series(1,4) n JOIN public.academy_payments p ON p.id=pg_temp.id(1300+n);
INSERT INTO private.notification_events (id,scope,academy_id,operation_id,effect_key,event_type,snapshot,status) VALUES
(pg_temp.id(1701),'TENANT',pg_temp.id(101),pg_temp.id(1601),'notification','MEMBERSHIP_INVITED','{"secret":"PRIVATE-EVENT"}','QUEUED'),
(pg_temp.id(1702),'TENANT',pg_temp.id(102),pg_temp.id(1603),'notification','MEMBERSHIP_INVITED','{}','QUEUED'),
(pg_temp.id(1703),'PLATFORM',NULL,pg_temp.id(1604),'notification','MEMBERSHIP_INVITED','{}','QUEUED');
INSERT INTO private.notification_deliveries (id,scope,academy_id,event_id,recipient_email,template,language,status,provider)
SELECT pg_temp.id(1800+n),e.scope,e.academy_id,e.id,'private-email-'||n||'@example.test','invitation','FR','QUEUED','BREVO'
FROM generate_series(1,3) n JOIN private.notification_events e ON e.id=pg_temp.id(1700+n);
INSERT INTO private.notification_payloads (delivery_id,scope,academy_id,body,purge_at)
SELECT id,scope,academy_id,'{"action_link":"PRIVATE-ACTION-LINK"}',now()+interval '1 day' FROM private.notification_deliveries;
INSERT INTO private.audit_log (id,scope,academy_id,operation_id,effect_key,actor_kind,actor_ref,action,resource_type,resource_id,occurred_at,reason,metadata)
SELECT pg_temp.id(1900+n),e.scope,e.academy_id,e.operation_id,'audit','SYSTEM','security-fixture','test','academy',coalesce(e.academy_id,pg_temp.id(999)),now(),'PRIVATE-REASON','{"private":"PRIVATE-AUDIT"}'
FROM generate_series(1,3) n JOIN private.notification_events e ON e.id=pg_temp.id(1700+n);
INSERT INTO private.course_ledger (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,package_id,delta,reason,occurred_at,reason_text)
VALUES(pg_temp.id(2001),pg_temp.id(101),pg_temp.id(1601),'ledger','SYSTEM','security-fixture',pg_temp.id(801),10,'PACKAGE_PURCHASE',now(),'PRIVATE-LEDGER-REASON');
INSERT INTO private.booking_events (id,academy_id,operation_id,effect_key,actor_kind,actor_ref,booking_id,event_type,after_status,occurred_at,booking_revision,metadata)
SELECT pg_temp.id(2100+n),pg_temp.id(101),pg_temp.id(1601),'booking-'||n,'SYSTEM','security-fixture',pg_temp.id(1000+n),'APPROVED','CONFIRMED',now(),1,'{"private":"PRIVATE-BOOKING-EVENT"}' FROM generate_series(1,2) n;
INSERT INTO private.academy_invitations (id,academy_id,email,requested_role_codes,requested_by,status,expires_at,operation_id,token_digest) VALUES
(pg_temp.id(2201),pg_temp.id(101),'invite-a@example.test',ARRAY['COACH'],pg_temp.id(10),'REQUESTED',now()+interval '1 day',pg_temp.id(1605),repeat('b',64)),
(pg_temp.id(2202),pg_temp.id(102),'invite-b@example.test',ARRAY['COACH'],pg_temp.id(8),'REQUESTED',now()+interval '1 day',pg_temp.id(1606),repeat('c',64));
INSERT INTO public.tournaments (id,academy_id,name,venue,category,starts_at,capacity,status) VALUES
(pg_temp.id(2301),pg_temp.id(101),'Test A','Venue A','Junior',now(),10,'OPEN'),
(pg_temp.id(2302),pg_temp.id(102),'Test B','Venue B','Junior',now(),10,'OPEN');
INSERT INTO public.communities (id,academy_id,name) VALUES (pg_temp.id(2401),pg_temp.id(101),'Community A'),(pg_temp.id(2402),pg_temp.id(102),'Community B');
INSERT INTO public.community_courses (id,academy_id,community_id,name) VALUES (pg_temp.id(2501),pg_temp.id(101),pg_temp.id(2401),'Course A'),(pg_temp.id(2502),pg_temp.id(102),pg_temp.id(2402),'Course B');
INSERT INTO public.platform_plans (id,code,version,name) VALUES (pg_temp.id(2601),'TEST-A',1,'Plan A'),(pg_temp.id(2602),'TEST-B',1,'Plan B');
INSERT INTO public.academy_subscriptions (id,academy_id,plan_id,status,starts_at) VALUES
(pg_temp.id(2701),pg_temp.id(101),pg_temp.id(2601),'ACTIVE',now()),(pg_temp.id(2702),pg_temp.id(102),pg_temp.id(2602),'ACTIVE',now());
SET CONSTRAINTS ALL IMMEDIATE;
