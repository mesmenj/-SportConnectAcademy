\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir support/helpers.sql
\ir support/security_helpers.sql
\ir support/security_fixtures.sql

-- Actors (academy A = 101, B = 102): 1 coach A + parent B, 2 coach A, 3/4 parents A,
-- 6 student A, 8 owner B, 10 owner A, 11 admin A, 12 manager A, 13 staff A with an
-- unusable guardian link, 15 platform admin, 16 super admin, 17 outsider,
-- 18 suspended profile, 19 suspended membership, 20 invited, 21 coach without coach
-- row, 22 membership without role. Fixture writes run as owner; reads as authenticated.
CREATE FUNCTION pg_temp.leaks(p_user integer, p_call text) RETURNS boolean
LANGUAGE sql AS $$ SELECT pg_temp.query_as(p_user, 'SELECT ' || p_call)::text LIKE '%PRIVATE%'; $$;
CREATE FUNCTION pg_temp.n(p_user integer, p_call text) RETURNS integer
LANGUAGE sql AS $$ SELECT jsonb_array_length(pg_temp.items(p_user, p_call)); $$;

-- Grants: read-only column subsets, fixed search_path, no anonymous entry point.
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public','private') AND has_function_privilege('anon', p.oid, 'EXECUTE')), 'anon executes no application function');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public','private') AND p.prosecdef AND NOT coalesce(p.proconfig::text LIKE '%search_path=pg_catalog%', false)), 'every definer pins search_path');
SELECT pg_temp.ok((SELECT count(*) = 19 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.provolatile = 's' AND p.prosecdef), 'the 19 read projections are STABLE and cannot write');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM information_schema.column_privileges
  WHERE grantee IN ('anon','authenticated') AND table_schema IN ('public','private') AND privilege_type <> 'SELECT'), 'no client write privilege on any column');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM information_schema.column_privileges
  WHERE grantee IN ('anon','authenticated','PUBLIC') AND table_schema = 'private'), 'no column of private schema granted');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM information_schema.column_privileges WHERE grantee = 'authenticated' AND (table_name, column_name) IN (
  ('players','birth_date'),('players','reported_age'),('players','gender'),('bookings','note'),('bookings','contract_snapshot'),
  ('bookings','amount_snapshot'),('player_packages','terms_snapshot'),('player_packages','total_price'),
  ('academy_invoices','customer_snapshot'),('academy_invoices','issuer_snapshot'),('player_evaluations','recorded_by'),
  ('academy_payments','operation_id'),('booking_attendance','recorded_by'))), 'sensitive columns only reachable through projections');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT to_jsonb(private.local_permission(pg_temp.id(101),''players.read''))')$q$,'42501','private helpers not callable by name');
SELECT pg_temp.rejects($q$SET LOCAL ROLE anon; SELECT public.get_access_context(NULL)$q$,'42501','anon cannot call projections');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT to_jsonb(count(birth_date)) FROM public.players')$q$,'42501','direct read of birth date denied even to owner');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT to_jsonb(count(note)) FROM public.bookings')$q$,'42501','direct read of booking note denied');

-- Academy A/B isolation on direct reads.
SELECT pg_temp.ok(pg_temp.visible(10,'public.players') = 2 AND pg_temp.visible(8,'public.players') = 1, 'owners see only their own academy players');
SELECT pg_temp.ok(pg_temp.visible(10,'public.academy_payments') = 3 AND pg_temp.visible(8,'public.academy_payments') = 1, 'owners see only their own academy payments');
SELECT pg_temp.ok(pg_temp.visible(10,'public.academies') = 1 AND pg_temp.visible(10,'public.academy_subscriptions') = 1 AND pg_temp.visible(10,'public.platform_plans') = 1, 'owner sees own academy, subscription and plan only');
SELECT pg_temp.ok(pg_temp.visible(10,'public.communities') = 1 AND pg_temp.visible(10,'public.community_courses') = 1 AND pg_temp.visible(10,'public.tournaments') = 1, 'tenant catalogues isolated');
SELECT pg_temp.ok(pg_temp.visible(10,'public.academy_memberships') = (SELECT count(*)::integer FROM public.academy_memberships WHERE academy_id = pg_temp.id(101)), 'owner sees all memberships of own academy only');
SELECT pg_temp.ok(pg_temp.visible(1,'public.players') = 2 AND (pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.players WHERE academy_id = pg_temp.id(102)') #>> '{}')::integer = 1, 'multi-tenant user gets role-specific access per academy');

-- Suspended, invited, roleless and unrelated accounts.
SELECT pg_temp.ok(pg_temp.visible(18,'public.players') = 0 AND pg_temp.visible(18,'public.user_profiles') = 0 AND pg_temp.visible(18,'public.academies') = 0, 'suspended profile sees nothing, not even itself');
SELECT pg_temp.ok(pg_temp.visible(19,'public.players') = 0 AND pg_temp.visible(19,'public.academies') = 0 AND pg_temp.visible(19,'public.academy_memberships') = 0, 'suspended membership grants no owner access');
SELECT pg_temp.ok(pg_temp.visible(20,'public.players') = 0 AND pg_temp.visible(20,'public.player_links') = 0, 'invited membership grants nothing');
SELECT pg_temp.ok(pg_temp.visible(22,'public.academies') = 0 AND pg_temp.visible(17,'public.academies') = 0 AND pg_temp.visible(17,'public.permissions','code') > 0, 'roleless and outsider see catalogues only');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(18,'SELECT public.get_access_context(NULL)')$q$,'42501','suspended profile rejected by projections');
SELECT pg_temp.ok(pg_temp.n(19,'public.list_my_academies()') = 0 AND pg_temp.n(20,'public.list_my_academies()') = 0, 'suspended and invited memberships not listed');

-- Forged identity claims are ignored: only the Auth subject counts.
SELECT pg_temp.ok((pg_temp.query_as(17,'SELECT to_jsonb(count(*)) FROM public.players',
  jsonb_build_object('role','service_role','academy_id',pg_temp.id(101),'app_metadata',jsonb_build_object('roles',jsonb_build_array('ACADEMY_OWNER')),
  'user_metadata',jsonb_build_object('platform_role','SUPER_ADMIN'))) #>> '{}')::integer = 0, 'role, academy and metadata claims confer nothing');
SELECT pg_temp.ok(pg_temp.query_as(17,'SELECT public.get_access_context(pg_temp.id(101))', jsonb_build_object('app_metadata',jsonb_build_object('academy_roles',jsonb_build_array('ACADEMY_OWNER')))) -> 'academy_permissions' = '[]'::jsonb, 'access context ignores metadata roles');

-- Staff (reception): operates bookings, no family contacts, no finance.
SELECT pg_temp.ok(pg_temp.visible(13,'public.players') = 2 AND pg_temp.visible(13,'public.bookings') = 3, 'staff sees academy players and bookings');
SELECT pg_temp.ok(pg_temp.visible(13,'public.player_links') = 0, 'staff sees no family links, including a guardian link without PARENT role');
SELECT pg_temp.ok(pg_temp.visible(13,'public.academy_payments') = 0 AND pg_temp.visible(13,'public.academy_invoices') = 0 AND pg_temp.visible(13,'public.player_evaluations') = 0, 'staff sees no finance or evaluations');
SELECT pg_temp.ok(pg_temp.visible(13,'public.academy_memberships') = 1 AND pg_temp.visible(13,'public.user_profiles') = 1, 'staff reads only own membership and profile rows');
SELECT pg_temp.ok(NOT pg_temp.leaks(13,'public.list_memberships(pg_temp.id(101))') AND NOT (pg_temp.items(13,'public.list_memberships(pg_temp.id(101))') @> jsonb_build_array(jsonb_build_object('user_id',pg_temp.id(3)))), 'staff roster shows names without phones or foreign user ids');
SELECT pg_temp.ok(NOT (pg_temp.query_as(13,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(301))') ? 'birth_date'), 'staff profile projection hides birth date');
SELECT pg_temp.ok(NOT pg_temp.leaks(13,'public.list_bookings(pg_temp.id(101),''2029-12-01'',''2030-02-01'')') AND pg_temp.n(13,'public.list_bookings(pg_temp.id(101),''2029-12-01'',''2030-02-01'')') = 3, 'staff booking projection without note or contract');
SELECT pg_temp.ok(NOT (pg_temp.items(13,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') -> 0 ?| ARRAY['total_price','purchased_sessions','terms_snapshot']), 'staff sees availability only on packages');
SELECT pg_temp.ok(pg_temp.n(13,'public.list_course_ledger(pg_temp.id(101),pg_temp.id(801))') = 0 AND pg_temp.n(13,'public.list_payments(pg_temp.id(101))') = 0 AND pg_temp.n(13,'public.list_notification_metadata(pg_temp.id(101))') = 0, 'staff has no ledger, payment or notification projection');

-- Manager: sport management, no finance, no membership administration.
SELECT pg_temp.ok(pg_temp.visible(12,'public.academy_payments') = 0 AND pg_temp.visible(12,'public.academy_invoices') = 0 AND pg_temp.n(12,'public.list_invoices(pg_temp.id(101))') = 0, 'manager isolated from finance');
SELECT pg_temp.ok(pg_temp.query_as(12,'SELECT public.get_invoice(pg_temp.id(101),pg_temp.id(1401))') IS NULL, 'manager cannot open an invoice by UUID');
SELECT pg_temp.ok(pg_temp.n(12,'public.list_invitations(pg_temp.id(101))') = 0 AND pg_temp.visible(12,'public.academy_memberships') = 1, 'manager cannot read invitations or other memberships');
SELECT pg_temp.ok(pg_temp.visible(12,'public.player_links') = 4 AND pg_temp.query_as(12,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(301))') ? 'birth_date', 'manager manages links and full player identity');
SELECT pg_temp.ok(NOT (pg_temp.items(12,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') -> 0 ? 'total_price') AND pg_temp.items(12,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') -> 0 ? 'remaining_sessions', 'manager sees credits but not package price');

-- Owner/Admin: finance and access administration of their own academy.
SELECT pg_temp.ok(pg_temp.visible(11,'public.academy_payments') = 3 AND pg_temp.n(11,'public.list_invoices(pg_temp.id(101))') = 3, 'admin reads academy finance');
SELECT pg_temp.ok(pg_temp.n(10,'public.list_invitations(pg_temp.id(101))') = 1 AND pg_temp.n(10,'public.list_invitations(pg_temp.id(102))') = 0, 'owner invitations scoped to own academy');
SELECT pg_temp.ok(pg_temp.query_as(10,'SELECT public.get_invoice(pg_temp.id(101),pg_temp.id(1401))') ? 'customer_snapshot', 'owner opens full invoice');
SELECT pg_temp.ok(pg_temp.items(10,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') -> 0 ? 'total_price', 'owner sees package price');
SELECT pg_temp.ok(pg_temp.n(10,'public.read_audit(pg_temp.id(101))') = 1 AND NOT pg_temp.leaks(10,'public.read_audit(pg_temp.id(101))') AND pg_temp.n(10,'public.read_audit(NULL)') = 0, 'owner audit: own tenant, no reason/metadata, no platform scope');
SELECT pg_temp.ok(pg_temp.n(10,'public.list_notification_metadata(pg_temp.id(101))') = 1 AND NOT pg_temp.leaks(10,'public.list_notification_metadata(pg_temp.id(101))')
  AND NOT (pg_temp.items(10,'public.list_notification_metadata(pg_temp.id(101))') -> 0 ? 'recipient_email'), 'notification metadata without recipient or payload');
SELECT pg_temp.ok(NOT pg_temp.leaks(10,'public.list_course_ledger(pg_temp.id(101),pg_temp.id(801))') AND pg_temp.n(10,'public.list_booking_events(pg_temp.id(101),pg_temp.id(1001))') = 1 AND NOT pg_temp.leaks(10,'public.list_booking_events(pg_temp.id(101),pg_temp.id(1001))'), 'history projections omit free-text reasons and metadata');

-- Coach: assigned sessions only, never family or finance data.
SELECT pg_temp.ok((pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.bookings WHERE academy_id = pg_temp.id(101)') #>> '{}')::integer = 1 AND pg_temp.visible(2,'public.bookings') = 2, 'coach sees bookings of own sessions only');
SELECT pg_temp.ok((pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.players WHERE academy_id = pg_temp.id(101)') #>> '{}')::integer = 1, 'coach sees only players of assigned sessions');
SELECT pg_temp.ok(pg_temp.visible(1,'public.player_evaluations') = 1 AND (pg_temp.query_as(1,$q$SELECT to_jsonb(count(*)) FROM public.player_evaluations WHERE comment = 'OTHER-COACH-NOTE'$q$) #>> '{}')::integer = 0, 'coach cannot read other coach evaluations');
SELECT pg_temp.ok((pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.player_links WHERE academy_id = pg_temp.id(101)') #>> '{}')::integer = 0
  AND (pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.academy_payments WHERE academy_id = pg_temp.id(101)') #>> '{}')::integer = 0, 'coach sees no family link or payment');
SELECT pg_temp.ok(NOT (pg_temp.query_as(1,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(301))') ?| ARRAY['birth_date','gender']) AND pg_temp.query_as(1,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(302))') IS NULL, 'coach profile: age only, unassigned player hidden');
SELECT pg_temp.ok(pg_temp.n(1,'public.list_sessions(pg_temp.id(101),''2029-12-01'',''2030-02-01'')') = 1 AND pg_temp.n(1,'public.list_service_offers(pg_temp.id(101))') = 1
  AND NOT (pg_temp.items(1,'public.list_service_offers(pg_temp.id(101))') -> 0 ? 'price'), 'coach sees own sessions and their offer without price');
SELECT pg_temp.ok(pg_temp.n(1,'public.list_booking_events(pg_temp.id(101),pg_temp.id(1002))') = 0 AND pg_temp.n(1,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') = 0, 'coach has no package or foreign booking history');
SELECT pg_temp.ok(pg_temp.visible(21,'public.bookings') = 0 AND pg_temp.visible(21,'public.players') = 0, 'COACH role without coach record has no assignment');

-- Parent/Student: active links only; guardians do not see each other.
SELECT pg_temp.ok(pg_temp.visible(3,'public.players') = 1 AND pg_temp.visible(6,'public.players') = 1 AND pg_temp.visible(4,'public.players') = 1, 'guardians and self see the linked player only');
SELECT pg_temp.ok(pg_temp.visible(3,'public.player_links') = 1 AND pg_temp.visible(6,'public.player_links') = 1, 'family member sees only own link, not other guardians');
SELECT pg_temp.ok(pg_temp.visible(3,'public.academy_payments') = 1 AND pg_temp.visible(6,'public.academy_invoices') = 1 AND pg_temp.visible(3,'public.user_profiles') = 1, 'family finance limited to linked player');
SELECT pg_temp.ok(pg_temp.query_as(3,'SELECT public.get_invoice(pg_temp.id(101),pg_temp.id(1401))') IS NOT NULL AND pg_temp.query_as(3,'SELECT public.get_invoice(pg_temp.id(101),pg_temp.id(1402))') IS NULL, 'parent opens own invoice, not an other family invoice');
SELECT pg_temp.ok(pg_temp.query_as(3,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(301))') ? 'birth_date' AND pg_temp.query_as(3,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(302))') IS NULL, 'parent sees full profile of own child only');
SELECT pg_temp.ok(pg_temp.n(3,'public.list_bookings(pg_temp.id(101),''2029-12-01'',''2030-02-01'',pg_temp.id(302))') = 0 AND pg_temp.n(3,'public.list_bookings(pg_temp.id(101),''2029-12-01'',''2030-02-01'')') = 2, 'player filter cannot widen parent access');
SELECT pg_temp.ok((pg_temp.items(3,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') -> 0 ->> 'available_sessions')::integer = 8
  AND NOT (pg_temp.items(3,'public.list_player_packages(pg_temp.id(101),pg_temp.id(301))') -> 0 ?| ARRAY['total_price','terms_snapshot']), 'parent sees A = R - H without contract terms');
SELECT pg_temp.ok(pg_temp.n(3,'public.list_course_ledger(pg_temp.id(101),pg_temp.id(801))') = 1 AND pg_temp.n(3,'public.list_course_ledger(pg_temp.id(101),pg_temp.id(802))') = 0, 'ledger limited to own child package');
SELECT pg_temp.ok(pg_temp.n(3,'public.list_service_offers(pg_temp.id(101))') = 2 AND pg_temp.items(3,'public.list_service_offers(pg_temp.id(101))') -> 0 ? 'price', 'family sees published offers with price');
SELECT pg_temp.ok(pg_temp.visible(3,'public.player_evaluations') = 2 AND pg_temp.visible(3,'public.booking_attendance','booking_id') = 2, 'family reads child attendance and evaluations');
SELECT pg_temp.ok(pg_temp.query_as(3,'SELECT public.get_access_context(pg_temp.id(101))') -> 'academy_roles' = '["PARENT"]'::jsonb
  AND NOT (pg_temp.query_as(3,'SELECT public.get_access_context(pg_temp.id(101))') -> 'academy_permissions' ? 'payments.record'), 'access context reflects parent bundle');

-- Forged UUIDs: another tenant's identifiers under one's own or foreign academy.
SELECT pg_temp.ok(pg_temp.query_as(3,'SELECT public.get_player_profile(pg_temp.id(102),pg_temp.id(303))') IS NULL AND pg_temp.query_as(3,'SELECT public.get_player_profile(pg_temp.id(101),pg_temp.id(303))') IS NULL, 'foreign player UUID returns nothing');
SELECT pg_temp.ok(pg_temp.query_as(10,'SELECT public.get_invoice(pg_temp.id(101),pg_temp.id(1403))') IS NULL AND pg_temp.query_as(10,'SELECT public.get_invoice(pg_temp.id(102),pg_temp.id(1403))') IS NULL, 'foreign invoice UUID returns nothing to owner A');
SELECT pg_temp.ok(pg_temp.n(10,'public.list_payments(pg_temp.id(102))') = 0 AND pg_temp.n(10,'public.list_players(pg_temp.id(102))') = 0 AND pg_temp.n(10,'public.list_course_ledger(pg_temp.id(101),pg_temp.id(803))') = 0, 'owner A cannot list tenant B through parameters');
SELECT pg_temp.ok(pg_temp.query_as(10,'SELECT public.get_access_context(pg_temp.id(102))') -> 'academy_id' = 'null'::jsonb, 'access context refuses foreign academy');
SELECT pg_temp.ok(pg_temp.query_as(1,'SELECT public.get_player_profile(pg_temp.id(102),pg_temp.id(303))') IS NOT NULL AND pg_temp.n(1,'public.list_payments(pg_temp.id(102))') = 1, 'same user acts as parent in B with parent scope');

-- Platform versus tenant.
SELECT pg_temp.ok(pg_temp.visible(15,'public.academies') = 2 AND pg_temp.n(15,'public.list_platform_academies()') = 2, 'platform admin reads academy metadata');
SELECT pg_temp.ok(pg_temp.visible(15,'public.players') = 0 AND pg_temp.visible(15,'public.bookings') = 0 AND pg_temp.visible(15,'public.academy_payments') = 0 AND pg_temp.visible(16,'public.player_links') = 0, 'platform roles are not a tenant bypass');
SELECT pg_temp.ok(pg_temp.n(15,'public.list_players(pg_temp.id(101))') = 0 AND pg_temp.query_as(16,'SELECT public.get_invoice(pg_temp.id(101),pg_temp.id(1401))') IS NULL, 'platform projections hide tenant data');
SELECT pg_temp.ok(pg_temp.n(15,'public.read_audit(NULL)') = 1 AND pg_temp.n(15,'public.read_audit(pg_temp.id(101))') = 0, 'platform audit separated from tenant audit');
SELECT pg_temp.ok(pg_temp.visible(15,'public.platform_roles','code') = 0 AND pg_temp.visible(16,'public.platform_roles','code') = 2 AND pg_temp.visible(15,'public.platform_plans') = 2, 'platform role catalogue restricted to super admin');
SELECT pg_temp.ok(pg_temp.n(10,'public.list_platform_academies()') = 0, 'tenant owner cannot list platform academies');

-- Input validation of projections.
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT public.list_players(pg_temp.id(101),NULL,NULL,0)')$q$,'22023','page size must be positive');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT public.list_players(pg_temp.id(101),NULL,NULL,101)')$q$,'22023','page size capped');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT public.list_players(pg_temp.id(101),now(),NULL,10)')$q$,'22023','cursor requires both parts');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT public.list_sessions(pg_temp.id(101),''2030-01-01'',''2031-06-01'')')$q$,'22023','session window capped at 366 days');
SELECT pg_temp.rejects($q$SELECT pg_temp.query_as(10,'SELECT public.list_bookings(pg_temp.id(101),''infinity'',''infinity'')')$q$,'22023','infinite window rejected');
SELECT pg_temp.ok(jsonb_array_length(pg_temp.query_as(10,'SELECT public.list_players(pg_temp.id(101),NULL,NULL,1)') -> 'items') = 1
  AND pg_temp.query_as(10,'SELECT public.list_players(pg_temp.id(101),NULL,NULL,1)') -> 'next_cursor' ? 'id', 'pagination returns a cursor when more rows exist');
SELECT pg_temp.ok((SELECT pg_temp.query_as(10, format('SELECT public.list_players(pg_temp.id(101),%L,%L,1)', c ->> 'at', c ->> 'id')) -> 'items' -> 0 ->> 'id'
  FROM (SELECT pg_temp.query_as(10,'SELECT public.list_players(pg_temp.id(101),NULL,NULL,1)') -> 'next_cursor' AS c) x)
  IS DISTINCT FROM (pg_temp.items(10,'public.list_players(pg_temp.id(101),NULL,NULL,1)') -> 0 ->> 'id'), 'cursor advances to the next player');

-- Revocation takes effect on the next statement: rights are never cached.
UPDATE private.academy_membership_roles SET revoked_at = now() WHERE membership_id = pg_temp.id(201) AND role_code = 'COACH';
SELECT pg_temp.ok((pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.bookings WHERE academy_id = pg_temp.id(101)') #>> '{}')::integer = 0 AND (pg_temp.query_as(1,'SELECT to_jsonb(count(*)) FROM public.players WHERE academy_id = pg_temp.id(101)') #>> '{}')::integer = 0, 'revoked coach role removes assignment access immediately');
SELECT pg_temp.ok(pg_temp.visible(1,'public.academy_payments') = 1, 'revocation in A leaves parent access in B intact');
UPDATE public.coaches SET active = false WHERE id = pg_temp.id(402);
SELECT pg_temp.ok(pg_temp.visible(2,'public.bookings') = 0, 'deactivated coach record loses assigned sessions');
UPDATE public.player_links SET revoked_at = now() WHERE id = pg_temp.id(1102);
SELECT pg_temp.ok(pg_temp.visible(4,'public.players') = 0 AND pg_temp.visible(4,'public.academy_payments') = 0 AND pg_temp.visible(4,'public.player_links') = 0, 'revoked guardian link removes child and finance access');
SELECT pg_temp.ok(pg_temp.visible(3,'public.players') = 1, 'other guardian unaffected by revocation');
UPDATE public.academy_memberships SET status = 'SUSPENDED' WHERE id = pg_temp.id(206);
SELECT pg_temp.ok(pg_temp.visible(6,'public.players') = 0 AND pg_temp.visible(6,'public.academy_invoices') = 0 AND pg_temp.n(6,'public.list_my_academies()') = 0, 'suspended student membership loses access immediately');
UPDATE public.user_profiles SET status = 'SUSPENDED' WHERE id = pg_temp.id(11);
SELECT pg_temp.ok(pg_temp.visible(11,'public.academy_payments') = 0 AND pg_temp.visible(11,'public.user_profiles') = 0, 'suspended admin profile loses access immediately');
UPDATE private.platform_user_roles SET revoked_at = now() WHERE user_id = pg_temp.id(15);
SELECT pg_temp.ok(pg_temp.visible(15,'public.academies') = 0 AND pg_temp.n(15,'public.read_audit(NULL)') = 0, 'revoked platform role loses metadata and audit access');
UPDATE public.academies SET status = 'SUSPENDED' WHERE id = pg_temp.id(101);
SELECT pg_temp.ok(pg_temp.visible(10,'public.players') = 0 AND pg_temp.visible(3,'public.players') = 0 AND pg_temp.visible(10,'public.academies') = 0, 'suspended academy blocks all tenant members');
SELECT pg_temp.ok(pg_temp.visible(16,'public.academies') = 2 AND pg_temp.visible(8,'public.players') = 1, 'suspended academy remains visible to platform, tenant B unaffected');

SELECT '1..' || currval('pg_temp.assertion_number');
ROLLBACK;
