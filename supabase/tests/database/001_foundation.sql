\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir support/helpers.sql

SELECT pg_temp.ok((SELECT count(*) = 41 FROM information_schema.tables WHERE table_schema IN ('public','private') AND table_type = 'BASE TABLE'), 'exactly 41 application tables');
SELECT pg_temp.ok((SELECT count(*) = 24 FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'), '24 public tables');
SELECT pg_temp.ok((SELECT count(*) = 17 FROM information_schema.tables WHERE table_schema = 'private' AND table_type = 'BASE TABLE'), '17 private tables');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM information_schema.tables WHERE table_schema IN ('public','private') AND table_name IN ('users','legacy_identity_map','legacy_entity_map','migration_issues','credit_holds')), 'no competing Auth, legacy or holds table');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM information_schema.columns WHERE table_schema IN ('public','private') AND column_name IN ('firebase_uid','legacy_uid','reserved_sessions','available_sessions','hold_exempt')), 'no Firebase mapping or authoritative availability column');
SELECT pg_temp.ok((SELECT count(*) = 5 FROM information_schema.columns WHERE table_schema = 'public' AND data_type = 'numeric' AND numeric_precision = 18 AND numeric_scale = 2), 'all five monetary columns numeric(18,2)');
SELECT pg_temp.ok((SELECT count(*) = 2 FROM pg_constraint WHERE contype = 'x' AND conrelid = 'public.sessions'::regclass), 'court and coach exclusion constraints');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname IN ('public','private') AND c.contype = 'f' AND (confdeltype <> 'r' OR confupdtype <> 'r')), 'all foreign keys restrict update/delete');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname IN ('public','private') AND c.confrelid = 'private.command_receipts'::regclass AND NOT (condeferrable AND condeferred)), 'receipt foreign keys initially deferred');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_policies WHERE schemaname IN ('public','private') AND (cmd <> 'SELECT' OR roles::text <> '{authenticated}')), 'only authenticated read policies; no client write policies');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind = 'r' AND NOT c.relrowsecurity), 'RLS enabled on every application table');
SELECT pg_temp.ok(NOT has_schema_privilege('anon', 'private', 'USAGE') AND NOT has_schema_privilege('authenticated','private','USAGE'), 'private schema inaccessible to clients');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind = 'r' AND (has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') OR has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))), 'all direct client table privileges revoked');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.prorettype = 'trigger'::regtype AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE'))), 'internal trigger functions not executable by clients');
SELECT pg_temp.ok((SELECT count(*) = 2 FROM public.platform_roles) AND (SELECT count(*) = 7 FROM public.academy_roles), 'two platform and seven fixed academy roles');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM public.permissions WHERE code IN ('migration.review','bookings.override.session_state')), 'no migration or forbidden override permission');
SELECT pg_temp.ok((SELECT count(*) = 5 FROM public.permissions WHERE code LIKE 'bookings.override.%'), 'exactly five allowed override permissions');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM private.academy_role_permissions WHERE role_code IN ('STAFF','COACH','MANAGER') AND (permission_code LIKE 'payments.%' OR permission_code LIKE 'invoices.%' OR permission_code IN ('packages.purchase','packages.activate_credit','course_ledger.adjust'))), 'Staff Coach Manager have no finance or credit mutation grants');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM private.academy_role_permissions WHERE role_code = 'MANAGER' AND permission_code IN ('memberships.invite','memberships.set_roles','memberships.suspend','memberships.transfer_owner')), 'Manager cannot administer memberships');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM private.academy_role_permissions WHERE role_code IN ('PARENT','STUDENT') AND permission_code IN ('bookings.schedule','bookings.approve','bookings.complete','bookings.archive','sessions.create','attendance.record','evaluations.record')), 'Parent Student have no staff operations');
SELECT pg_temp.ok((SELECT count(*) = 15 FROM private.academy_role_permissions WHERE permission_code LIKE 'bookings.override.%') AND NOT EXISTS (SELECT FROM private.academy_role_permissions WHERE permission_code LIKE 'bookings.override.%' AND role_code NOT IN ('ACADEMY_OWNER','ACADEMY_ADMIN','MANAGER')), 'overrides assigned only to Owner Admin Manager');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM private.platform_role_permissions WHERE permission_code LIKE 'players.%' OR permission_code LIKE 'payments.%' OR permission_code LIKE 'bookings.%'), 'platform role is not a tenant bypass');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM private.academy_role_permissions WHERE role_code <> 'ACADEMY_OWNER' AND permission_code = 'memberships.transfer_owner'), 'only Owner may transfer ownership');

\ir support/fixtures.sql

SELECT pg_temp.rejects($q$INSERT INTO public.user_profiles (id,display_name,preferred_language,status) VALUES(pg_temp.id(90),'Unregistered','FR','ACTIVE')$q$,'23503','profile must reference auth.users');
SELECT pg_temp.rejects($q$DELETE FROM auth.users WHERE id=pg_temp.id(1)$q$,'23503','Auth deletion cannot cascade through application history');
SELECT pg_temp.rejects($q$UPDATE public.players SET academy_id=pg_temp.id(102) WHERE id=pg_temp.id(301)$q$,'23514','tenant identity immutable');
SELECT pg_temp.rejects($q$INSERT INTO public.coaches (academy_id,membership_id) VALUES(pg_temp.id(101),pg_temp.id(208))$q$,'23503','coach cannot reference membership in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.package(804,101,303,701)$q$,'23503','package cannot reference player in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.package(804,101,301,703)$q$,'23503','package cannot reference offer in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,401,502,602,'2030-02-01 10:00Z','2030-02-01 11:00Z')$q$,'23503','session cannot reference stadium/court in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,401,503,601,'2030-02-01 10:00Z','2030-02-01 11:00Z')$q$,'23503','court must belong to chosen stadium');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,403,501,601,'2030-02-01 10:00Z','2030-02-01 11:00Z')$q$,'23503','session cannot use coach in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,902,301,802)$q$,'23503','booking cannot use another player package in same academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,903,301,801)$q$,'23503','booking cannot use session in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,902,301,803)$q$,'23503','booking cannot use package in other academy');
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,902,301,NULL,'CONFIRMED')$q$,'23514','operational confirmation requires package');
SELECT pg_temp.rejects($q$UPDATE public.player_packages SET remaining_sessions=-1 WHERE id=pg_temp.id(801)$q$,'23514','negative remaining credit rejected');
SELECT pg_temp.rejects($q$UPDATE public.sessions SET occupied_places=-1 WHERE id=pg_temp.id(901)$q$,'23514','negative occupied places rejected');
UPDATE public.sessions SET occupied_places=3 WHERE id=pg_temp.id(901);
SELECT pg_temp.ok((SELECT occupied_places > capacity FROM public.sessions WHERE id=pg_temp.id(901)), 'capacity override structurally possible without disabling constraints');

INSERT INTO public.player_links (id,academy_id,player_id,user_id,relationship,is_primary,is_financial_contact) VALUES
(pg_temp.id(1101),pg_temp.id(101),pg_temp.id(301),pg_temp.id(3),'GUARDIAN',true,true),
(pg_temp.id(1102),pg_temp.id(101),pg_temp.id(301),pg_temp.id(4),'GUARDIAN',false,false),
(pg_temp.id(1103),pg_temp.id(101),pg_temp.id(301),pg_temp.id(6),'SELF',false,false);
SELECT pg_temp.ok((SELECT count(*)=2 FROM public.player_links WHERE player_id=pg_temp.id(301) AND relationship='GUARDIAN'), 'multiple guardians coexist');
SELECT pg_temp.ok((SELECT count(*)=3 FROM public.player_links WHERE player_id=pg_temp.id(301)), 'SELF and guardians coexist');
SELECT pg_temp.rejects($q$UPDATE public.player_links SET is_primary=true WHERE id=pg_temp.id(1102)$q$,'23505','two active primary contacts rejected');
SELECT pg_temp.rejects($q$UPDATE public.player_links SET is_financial_contact=true WHERE id=pg_temp.id(1102)$q$,'23505','two active financial contacts rejected');
SELECT pg_temp.rejects($q$INSERT INTO public.player_links (academy_id,player_id,user_id,relationship) VALUES(pg_temp.id(101),pg_temp.id(301),pg_temp.id(7),'SELF')$q$,'23505','second active SELF rejected');
SELECT pg_temp.rejects($q$INSERT INTO public.player_links (academy_id,player_id,user_id,relationship) VALUES(pg_temp.id(101),pg_temp.id(301),pg_temp.id(3),'GUARDIAN')$q$,'23505','duplicate active user/player link rejected');
SELECT pg_temp.rejects($q$INSERT INTO public.player_links (academy_id,player_id,user_id,relationship) VALUES(pg_temp.id(101),pg_temp.id(301),pg_temp.id(8),'GUARDIAN')$q$,'23503','guardian requires local membership');
UPDATE public.player_links SET revoked_at=now() WHERE id=pg_temp.id(1101);
UPDATE public.player_links SET is_primary=true,is_financial_contact=true WHERE id=pg_temp.id(1102);
SELECT pg_temp.ok((SELECT is_primary AND is_financial_contact FROM public.player_links WHERE id=pg_temp.id(1102)), 'contact reassignment possible after revocation');
SELECT pg_temp.ok((SELECT count(*)=2 FROM public.service_offers WHERE academy_id=pg_temp.id(101) AND duration_minutes=60 AND status='PUBLISHED'), 'same duration and overlapping ages allowed for distinct offers');
SELECT pg_temp.rejects($q$SELECT pg_temp.offer(704,101,710,2)$q$,'23505','only one published version per academy/offer_key');
SELECT pg_temp.ok((SELECT count(*)=2 FROM public.service_offers WHERE offer_key=pg_temp.id(710)), 'same offer key allowed across academies');
SELECT pg_temp.rejects($q$UPDATE public.service_offers SET price_basis=NULL WHERE id=pg_temp.id(701)$q$,'23502','price basis mandatory without fallback');
SELECT pg_temp.rejects($q$SELECT pg_temp.offer(704,101,740,1,100.25,'XAF')$q$,'23514','fractional XAF rejected');
SELECT pg_temp.offer(704,101,740,1,1000,'XAF');
SELECT pg_temp.ok((SELECT price=1000 FROM public.service_offers WHERE id=pg_temp.id(704)), 'integer XAF accepted');
SELECT pg_temp.offer(705,101,750,1,12.34,'EUR');
SELECT pg_temp.offer(706,101,760,1,12.34,'USD');
SELECT pg_temp.offer(707,101,770,1,12.34,'AED');
SELECT pg_temp.offer(708,101,780,1,12.34,'MAD');
SELECT pg_temp.ok((SELECT count(*)=4 FROM public.service_offers WHERE price=12.34 AND currency IN ('EUR','USD','AED','MAD')), 'two decimals accepted for EUR USD AED MAD');
SELECT pg_temp.rejects($q$UPDATE public.player_packages SET total_price=100.25 WHERE id=pg_temp.id(801)$q$,'23514','fractional XAF package rejected');
SELECT pg_temp.rejects($q$UPDATE public.bookings SET amount_snapshot=100.25 WHERE id=pg_temp.id(1001)$q$,'23514','fractional XAF booking rejected');
SELECT pg_temp.rejects($q$UPDATE public.service_offers SET price='NaN' WHERE id=pg_temp.id(705)$q$,'23514','NaN monetary value rejected');
SELECT pg_temp.rejects($q$UPDATE public.service_offers SET currency='GBP' WHERE id=pg_temp.id(705)$q$,'23514','unsupported currency rejected');

SELECT pg_temp.ok((SELECT count(*)=2 FROM public.sessions WHERE academy_id=pg_temp.id(101)), 'adjacent court and coach slots accepted');
SELECT pg_temp.ok((SELECT count(*)=2 FROM public.sessions WHERE starts_at='2030-01-01 10:00Z'), 'same Auth user may coach in two academies concurrently');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,402,501,601,'2030-01-01 10:30Z','2030-01-01 11:30Z')$q$,'23P01','court collision rejected for different coach');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,401,501,603,'2030-01-01 10:30Z','2030-01-01 11:30Z')$q$,'23P01','local coach collision rejected for different court');
UPDATE public.sessions SET status='CLOSED' WHERE id=pg_temp.id(901);
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,402,501,601,'2030-01-01 10:00Z','2030-01-01 11:00Z')$q$,'23P01','CLOSED session still blocks court');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(904,101,701,401,501,603,'2030-01-01 10:00Z','2030-01-01 11:00Z')$q$,'23P01','CLOSED session still blocks coach');
UPDATE public.sessions SET status='CANCELLED' WHERE id=pg_temp.id(901);
SELECT pg_temp.session(904,101,701,401,501,601,'2030-01-01 10:00Z','2030-01-01 11:00Z');
SELECT pg_temp.ok((SELECT count(*)=2 FROM public.sessions WHERE academy_id=pg_temp.id(101) AND starts_at='2030-01-01 10:00Z'), 'CANCELLED session frees both resources');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(905,101,701,402,501,603,'2030-01-01 10:00Z','2030-01-01 10:00Z')$q$,'23514','zero duration rejected');
SELECT pg_temp.rejects($q$SELECT pg_temp.session(905,101,701,402,501,603,'2030-01-01 10:00Z','2030-01-01 19:00Z')$q$,'23514','duration over eight hours rejected');
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,901,301,801)$q$,'23505','PENDING plus PENDING rejected');
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,901,301,801,'CONFIRMED')$q$,'23505','PENDING plus CONFIRMED rejected');
UPDATE public.bookings SET deleted_at=now() WHERE id=pg_temp.id(1001);
SELECT pg_temp.rejects($q$SELECT pg_temp.booking(1002,101,901,301,801)$q$,'23505','deleted_at cannot bypass active booking uniqueness');
UPDATE public.bookings SET status='CANCELLED' WHERE id=pg_temp.id(1001);
SELECT pg_temp.booking(1002,101,901,301,801);
SELECT pg_temp.ok((SELECT count(*)=2 FROM public.bookings WHERE session_id=pg_temp.id(901)), 'new UUID accepted after CANCELLED');
UPDATE public.bookings SET status='REJECTED' WHERE id=pg_temp.id(1002);
SELECT pg_temp.booking(1003,101,901,301,801,'COMPLETED');
SELECT pg_temp.booking(1004,101,901,301,801);
SELECT pg_temp.ok((SELECT count(*)=4 FROM public.bookings WHERE session_id=pg_temp.id(901)), 'REJECTED and COMPLETED historical rows do not block active UUID');
SELECT pg_temp.rejects($q$UPDATE public.bookings SET completion_source=NULL WHERE id=pg_temp.id(1003)$q$,'23514','completion source required');

-- RLS exercised as actual roles, not only by inspecting catalog flags.
SELECT pg_temp.rejects($q$SET LOCAL ROLE anon; SELECT * FROM public.players$q$,'42501','anon direct SELECT denied');
SELECT pg_temp.rejects($q$SET LOCAL ROLE authenticated; SELECT * FROM public.players$q$,'42501','authenticated direct SELECT denied');
SELECT pg_temp.rejects($q$SET LOCAL ROLE authenticated; SELECT * FROM private.course_ledger$q$,'42501','authenticated cannot access private ledger');
-- Temporary grant isolates RLS itself from GRANT protection; rolled back at end.
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.players TO anon, authenticated;
CREATE TEMP TABLE rls_observations (role_name text, visible integer);
GRANT INSERT ON pg_temp.rls_observations TO anon, authenticated;
SET LOCAL ROLE anon;
INSERT INTO pg_temp.rls_observations SELECT 'anon',count(*) FROM public.players;
RESET ROLE;
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.rls_observations SELECT 'authenticated',count(*) FROM public.players;
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=2 AND bool_and(visible=0) FROM pg_temp.rls_observations), 'RLS returns zero rows even after temporary SELECT grant');
GRANT INSERT ON public.players TO authenticated;
SELECT pg_temp.rejects($q$SET LOCAL ROLE authenticated; INSERT INTO public.players (academy_id,first_name,last_name,status) VALUES('00000000-0000-0000-0000-000000000101','Forged','Player','ACTIVE')$q$,'42501','RLS rejects authenticated INSERT even after temporary grant');

SELECT '1..' || currval('pg_temp.assertion_number');
ROLLBACK;
