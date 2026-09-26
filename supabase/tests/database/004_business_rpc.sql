\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir support/helpers.sql
\ir support/security_helpers.sql
\ir support/security_fixtures.sql

-- Commands run as `authenticated` with the actor's Auth subject (see 003 for the
-- actor list). Data is built through the RPCs themselves; the only direct writes
-- are marked "time passes" (moving a session into the past) and one legacy debit.
-- Each RPC normally commits alone; receipt FKs and scope triggers are deferred to
-- commit. Here they are deferred for the whole suite, then all checked at the end.
SET CONSTRAINTS ALL DEFERRED;
CREATE TEMP TABLE vars (k text PRIMARY KEY, v uuid);
GRANT SELECT ON vars TO authenticated;
CREATE FUNCTION pg_temp.v(p_key text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM pg_temp.vars WHERE k = p_key; $$;
CREATE FUNCTION pg_temp.put(p_key text, p_value text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO pg_temp.vars VALUES (p_key, p_value::uuid) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
$$;
-- A statement's subqueries share its start snapshot, so every command runs in
-- its own statement (exec) and is checked in the next one (last).
CREATE TEMP TABLE last_result (r jsonb);
CREATE FUNCTION pg_temp.exec(p_user integer, p_call text) RETURNS void LANGUAGE sql AS $$
  DELETE FROM pg_temp.last_result;
  INSERT INTO pg_temp.last_result SELECT pg_temp.query_as(p_user, 'SELECT public.' || p_call);
$$;
CREATE FUNCTION pg_temp.last() RETURNS jsonb LANGUAGE sql AS $$ SELECT r FROM pg_temp.last_result; $$;
CREATE FUNCTION pg_temp.run(p_user integer, p_call text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.query_as(p_user, 'SELECT public.' || p_call);
$$;
CREATE FUNCTION pg_temp.fails(p_user integer, p_call text, p_code text, p_label text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_message text;
BEGIN
  BEGIN
    PERFORM pg_temp.run(p_user, p_call);
  EXCEPTION WHEN OTHERS THEN
    v_message := SQLERRM;
  END;
  RETURN pg_temp.ok(v_message = p_code, p_label || ' [' || coalesce(v_message, 'NO ERROR') || ']');
END;
$$;
CREATE FUNCTION pg_temp.booking(p_key text) RETURNS public.bookings LANGUAGE sql AS $$
  SELECT * FROM public.bookings WHERE id = pg_temp.v(p_key);
$$;
CREATE FUNCTION pg_temp.r(p_key text) RETURNS integer LANGUAGE sql AS $$
  SELECT remaining_sessions FROM public.player_packages WHERE id = pg_temp.v(p_key);
$$;
CREATE FUNCTION pg_temp.h(p_package uuid) RETURNS integer LANGUAGE sql AS $$
  SELECT private.package_hold(pg_temp.id(101), p_package);
$$;

-- Catalogue of client commands.
SELECT pg_temp.ok((SELECT count(*) = 65 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.provolatile = 'v' AND p.prosecdef
    AND p.proconfig::text LIKE '%search_path=pg_catalog%' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')), '65 client RPCs (59 3C + 6 3D): definer, pinned path, authenticated only');
SELECT pg_temp.ok(NOT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND p.proname NOT IN ('active_actor','local_permission','platform_permission','can_read_player','can_read_booking',
      'can_read_session','can_read_coach','can_read_offer','can_read_membership','can_read_link','can_read_finance',
      'can_read_plan','can_read_resource')), 'command internals not executable by clients');

-- Offers and exact money validation (§5).
SELECT pg_temp.fails(12, $q$create_offer(pg_temp.id(101),'O','TENNIS','GROUP',5,25,10,'100','XAF',NULL,gen_random_uuid())$q$, 'PRICE_BASIS_REQUIRED', 'price basis mandatory');
SELECT pg_temp.fails(12, $q$create_offer(pg_temp.id(101),'O','TENNIS','GROUP',5,25,10,'100.5','XAF','PACKAGE',gen_random_uuid())$q$, 'INVALID_AMOUNT', 'XAF refuses decimals');
SELECT pg_temp.fails(12, $q$create_offer(pg_temp.id(101),'O','TENNIS','GROUP',5,25,10,'12.345','EUR','PACKAGE',gen_random_uuid())$q$, 'INVALID_AMOUNT', 'three decimals rejected before cast');
SELECT pg_temp.fails(12, $q$create_offer(pg_temp.id(101),'O','TENNIS','GROUP',5,25,10,'1e5','EUR','PACKAGE',gen_random_uuid())$q$, 'INVALID_AMOUNT', 'scientific notation rejected');
SELECT pg_temp.fails(12, $q$create_offer(pg_temp.id(101),'O','TENNIS','GROUP',5,25,10,'10','GBP','PACKAGE',gen_random_uuid())$q$, 'INVALID_CURRENCY', 'unsupported currency rejected');
SELECT pg_temp.fails(13, $q$create_offer(pg_temp.id(101),'O','TENNIS','GROUP',5,25,10,'10','XAF','PACKAGE',gen_random_uuid())$q$, 'FORBIDDEN', 'staff cannot edit offers');
SELECT pg_temp.exec(12, $q$create_offer(pg_temp.id(101),'Euro','PADEL','PRIVATE',5,25,1,'12.34','EUR','SESSION',gen_random_uuid())$q$);
SELECT pg_temp.ok((pg_temp.last() ->> 'version') = '1'
  AND EXISTS (SELECT FROM public.service_offers WHERE name = 'Euro' AND price = 12.34 AND status = 'DRAFT'), 'two-decimal EUR price stored exactly as draft');
SELECT pg_temp.put('v1', pg_temp.run(12, $q$create_offer(pg_temp.id(101),'Tennis group','TENNIS','GROUP',5,25,10,'100000','XAF','PACKAGE',gen_random_uuid(),60)$q$) ->> 'offer_id');
SELECT pg_temp.exec(12, $q$publish_offer(pg_temp.id(101),pg_temp.v('v1'),gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'PUBLISHED', 'draft published');
SELECT pg_temp.put('series', (SELECT offer_key::text FROM public.service_offers WHERE id = pg_temp.v('v1')));
SELECT pg_temp.put('offer', pg_temp.run(12, $q$create_offer(pg_temp.id(101),'Tennis group','TENNIS','GROUP',5,25,10,'100000','XAF','PACKAGE',gen_random_uuid(),60,pg_temp.v('series'))$q$) ->> 'offer_id');
SELECT pg_temp.exec(12, $q$publish_offer(pg_temp.id(101),pg_temp.v('offer'),gen_random_uuid())$q$);
SELECT pg_temp.ok((SELECT version = 2 AND supersedes_id = pg_temp.v('v1') FROM public.service_offers WHERE id = pg_temp.v('offer'))
  AND (SELECT status FROM public.service_offers WHERE id = pg_temp.v('v1')) = 'RETIRED'
  AND (SELECT count(*) = 1 FROM public.service_offers WHERE offer_key = pg_temp.v('series') AND status = 'PUBLISHED'), 'new version supersedes and retires the old one atomically');
SELECT pg_temp.fails(12, $q$publish_offer(pg_temp.id(101),pg_temp.v('offer'),gen_random_uuid())$q$, 'INVALID_STATE', 'published version is immutable');

-- Resources and sessions: court and local coach exclusions at write time.
SELECT pg_temp.put('stadium', pg_temp.run(12, $q$create_stadium(pg_temp.id(101),'Central','Rue 1',gen_random_uuid())$q$) ->> 'stadium_id');
SELECT pg_temp.put('court', pg_temp.run(12, $q$create_court(pg_temp.id(101),pg_temp.v('stadium'),1,gen_random_uuid())$q$) ->> 'court_id');
SELECT pg_temp.fails(12, $q$create_court(pg_temp.id(101),pg_temp.v('stadium'),1,gen_random_uuid())$q$, 'NAME_TAKEN', 'court number unique per stadium');
SELECT pg_temp.put('s1', pg_temp.run(12, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-01-06 10:00Z','2031-01-06 11:00Z',1,gen_random_uuid(),NULL,pg_temp.v('court'))$q$) ->> 'session_id');
SELECT pg_temp.ok((SELECT stadium_id = pg_temp.v('stadium') FROM public.sessions WHERE id = pg_temp.v('s1')), 'stadium derived from the chosen court');
SELECT pg_temp.fails(12, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(402),'2031-01-06 10:30Z','2031-01-06 11:30Z',1,gen_random_uuid(),NULL,pg_temp.v('court'))$q$, 'COURT_CONFLICT', 'same court overlap refused');
SELECT pg_temp.fails(12, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-01-06 10:30Z','2031-01-06 11:30Z',1,gen_random_uuid())$q$, 'COACH_CONFLICT', 'same local coach overlap refused');
SELECT pg_temp.put('s2', pg_temp.run(12, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-01-06 11:00Z','2031-01-06 12:00Z',2,gen_random_uuid(),NULL,pg_temp.v('court'))$q$) ->> 'session_id');
SELECT pg_temp.ok(pg_temp.v('s2') IS NOT NULL, 'adjacent half-open interval accepted');
SELECT pg_temp.fails(12, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2020-01-01 10:00Z','2020-01-01 11:00Z',1,gen_random_uuid())$q$, 'INVALID_SESSION', 'session must start in the future');
SELECT pg_temp.fails(12, $q$create_session(pg_temp.id(101),pg_temp.v('v1'),pg_temp.id(401),'2031-02-01 10:00Z','2031-02-01 11:00Z',1,gen_random_uuid())$q$, 'OFFER_UNAVAILABLE', 'retired offer cannot be scheduled');
SELECT pg_temp.fails(1, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-02-01 10:00Z','2031-02-01 11:00Z',1,gen_random_uuid())$q$, 'FORBIDDEN', 'coach cannot create sessions');
SELECT pg_temp.put('s3', pg_temp.run(13, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-01-07 10:00Z','2031-01-07 11:00Z',2,gen_random_uuid())$q$) ->> 'session_id');
SELECT pg_temp.put('s4', pg_temp.run(13, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-01-08 10:00Z','2031-01-08 11:00Z',2,gen_random_uuid())$q$) ->> 'session_id');
SELECT pg_temp.put('s5', pg_temp.run(12, $q$create_session(pg_temp.id(101),pg_temp.id(701),pg_temp.id(402),'2031-01-09 10:00Z','2031-01-09 11:00Z',2,gen_random_uuid())$q$) ->> 'session_id');
SELECT pg_temp.put('s6', pg_temp.run(12, $q$create_session(pg_temp.id(101),pg_temp.id(701),pg_temp.id(402),'2031-01-10 10:00Z','2031-01-10 11:00Z',2,gen_random_uuid())$q$) ->> 'session_id');
SELECT pg_temp.ok(pg_temp.v('s3') IS NOT NULL AND pg_temp.v('s6') IS NOT NULL, 'staff may create one-off sessions');

-- Packages, payments and invoices: credits only after an exact confirmed payment.
SELECT pg_temp.fails(12, $q$purchase_package(pg_temp.id(101),pg_temp.id(301),pg_temp.v('offer'),gen_random_uuid())$q$, 'FORBIDDEN', 'manager cannot sell packages');
SELECT pg_temp.put('pkg', pg_temp.run(10, $q$purchase_package(pg_temp.id(101),pg_temp.id(301),pg_temp.v('offer'),gen_random_uuid())$q$) ->> 'package_id');
SELECT pg_temp.ok((SELECT status = 'PENDING' AND remaining_sessions = 0 AND total_price = 100000 AND purchased_sessions = 10
  AND terms_snapshot ->> 'price_basis' = 'PACKAGE' FROM public.player_packages WHERE id = pg_temp.v('pkg')), 'purchase freezes contract without credit');
SELECT pg_temp.fails(10, $q$activate_package_credit(pg_temp.id(101),pg_temp.v('pkg'),gen_random_uuid())$q$, 'PAYMENT_REQUIRED', 'no credit before payment');
SELECT pg_temp.fails(10, $q$record_payment(pg_temp.id(101),pg_temp.id(301),pg_temp.v('pkg'),'100000','EUR','CASH',gen_random_uuid())$q$, 'CURRENCY_MISMATCH', 'payment currency equals package currency');
SELECT pg_temp.put('pay_low', pg_temp.run(10, $q$record_payment(pg_temp.id(101),pg_temp.id(301),pg_temp.v('pkg'),'99999','XAF','CASH',gen_random_uuid())$q$) ->> 'payment_id');
SELECT pg_temp.fails(10, $q$confirm_payment(pg_temp.id(101),pg_temp.v('pay_low'),gen_random_uuid())$q$, 'AMOUNT_MISMATCH', 'partial payment cannot confirm package');
SELECT pg_temp.fails(13, $q$record_payment(pg_temp.id(101),pg_temp.id(301),pg_temp.v('pkg'),'100000','XAF','CASH',gen_random_uuid())$q$, 'FORBIDDEN', 'staff has no finance command');
SELECT pg_temp.put('pay', pg_temp.run(11, $q$record_payment(pg_temp.id(101),pg_temp.id(301),pg_temp.v('pkg'),'100000.00','XAF','CASH',gen_random_uuid())$q$) ->> 'payment_id');
SELECT pg_temp.fails(12, $q$confirm_payment(pg_temp.id(101),pg_temp.v('pay'),gen_random_uuid())$q$, 'FORBIDDEN', 'manager cannot confirm payments');
SELECT pg_temp.exec(11, $q$confirm_payment(pg_temp.id(101),pg_temp.v('pay'),gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'CONFIRMED'
  AND (SELECT payment_state FROM public.player_packages WHERE id = pg_temp.v('pkg')) = 'CONFIRMED', 'admin confirms exact payment');
SELECT pg_temp.put('pay2', pg_temp.run(11, $q$record_payment(pg_temp.id(101),pg_temp.id(301),pg_temp.v('pkg'),'100000','XAF','BANK_TRANSFER',gen_random_uuid())$q$) ->> 'payment_id');
SELECT pg_temp.fails(11, $q$confirm_payment(pg_temp.id(101),pg_temp.v('pay2'),gen_random_uuid())$q$, 'PAYMENT_ALREADY_CONFIRMED', 'one confirmed payment per package');
SELECT pg_temp.exec(10, $q$activate_package_credit(pg_temp.id(101),pg_temp.v('pkg'),gen_random_uuid())$q$);
SELECT pg_temp.ok((pg_temp.last() ->> 'available_sessions')::integer = 10
  AND pg_temp.r('pkg') = 10 AND (SELECT count(*) = 1 FROM private.course_ledger WHERE package_id = pg_temp.v('pkg') AND reason = 'PACKAGE_PURCHASE' AND delta = 10), 'activation writes one purchase entry and cache');
SELECT pg_temp.fails(10, $q$activate_package_credit(pg_temp.id(101),pg_temp.v('pkg'),gen_random_uuid())$q$, 'ALREADY_ACTIVATED', 'credit activated once');
SELECT pg_temp.exec(10, $q$issue_invoice(pg_temp.id(101),pg_temp.v('pay'),'INV-2031-1',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'ISSUED'
  AND (SELECT status = 'PAID' AND amount = 100000 AND session_count = 10 FROM public.academy_invoices WHERE number = 'INV-2031-1'), 'invoice snapshots the confirmed payment');
SELECT pg_temp.fails(10, $q$issue_invoice(pg_temp.id(101),pg_temp.v('pay'),'INV-2031-2',gen_random_uuid())$q$, 'ALREADY_INVOICED', 'one invoice per payment');
SELECT pg_temp.fails(10, $q$issue_invoice(pg_temp.id(101),pg_temp.v('pay2'),'INV-2031-1',gen_random_uuid())$q$, 'INVOICE_NUMBER_TAKEN', 'invoice number unique per academy');
SELECT pg_temp.fails(12, $q$adjust_course_credit(pg_temp.id(101),pg_temp.v('pkg'),-9,'fixture',gen_random_uuid())$q$, 'FORBIDDEN', 'manager cannot adjust credits');
SELECT pg_temp.fails(10, $q$adjust_course_credit(pg_temp.id(101),pg_temp.v('pkg'),-9,'  ',gen_random_uuid())$q$, 'REASON_REQUIRED', 'adjustment needs a reason');
SELECT pg_temp.fails(10, $q$adjust_course_credit(pg_temp.id(101),pg_temp.v('pkg'),-11,'too much',gen_random_uuid())$q$, 'NEGATIVE_BALANCE', 'R never negative');
SELECT pg_temp.exec(10, $q$adjust_course_credit(pg_temp.id(101),pg_temp.v('pkg'),-9,'keep one credit',gen_random_uuid())$q$);
SELECT pg_temp.ok((pg_temp.last() ->> 'remaining_sessions')::integer = 1, 'owner adjusts to R = 1');

-- Request, idempotent retry and approval.
SELECT pg_temp.put('b1', pg_temp.run(3, format($q$request_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(301),pg_temp.v('pkg'),%L)$q$, pg_temp.id(90001))) ->> 'booking_id');
SELECT pg_temp.ok((pg_temp.booking('b1')).status = 'PENDING' AND (SELECT occupied_places FROM public.sessions WHERE id = pg_temp.v('s1')) = 0, 'family request is PENDING without place or hold');
SELECT pg_temp.exec(3, format($q$request_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(301),pg_temp.v('pkg'),%L)$q$, pg_temp.id(90001)));
SELECT pg_temp.ok(pg_temp.last() ->> 'booking_id' = pg_temp.v('b1')::text
  AND (SELECT count(*) = 1 FROM public.bookings WHERE session_id = pg_temp.v('s1')), 'retry with same key returns the receipt, no second effect');
SELECT pg_temp.fails(3, format($q$request_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(301),pg_temp.v('pkg'),%L,'changed')$q$, pg_temp.id(90001)), 'IDEMPOTENCY_CONFLICT', 'same key with another payload refused');
SELECT pg_temp.ok((SELECT count(*) = 1 FROM private.booking_events e WHERE e.booking_id = pg_temp.v('b1') AND e.event_type = 'REQUESTED')
  AND (SELECT count(*) = 1 FROM private.notification_events n WHERE n.booking_id = pg_temp.v('b1') AND n.event_type = 'BOOKING_REQUESTED')
  AND (SELECT count(DISTINCT x) = 1 FROM (SELECT operation_id x FROM private.booking_events WHERE booking_id = pg_temp.v('b1')
    UNION ALL SELECT operation_id FROM private.notification_events WHERE booking_id = pg_temp.v('b1')
    UNION ALL SELECT operation_id FROM private.audit_log WHERE resource_id = pg_temp.v('b1')) o)
  AND EXISTS (SELECT FROM private.command_receipts r WHERE r.rpc_name = 'request_booking' AND r.operation_key = pg_temp.id(90001)), 'event, outbox, audit and receipt share one operation');
SELECT pg_temp.fails(3, $q$request_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid())$q$, 'NOT_FOUND', 'parent cannot book an unlinked player');
SELECT pg_temp.fails(6, $q$request_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid())$q$, 'DUPLICATE_ACTIVE_BOOKING', 'one active booking per player and session');
SELECT pg_temp.fails(1, $q$request_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid())$q$, 'FORBIDDEN', 'coach cannot request bookings');
SELECT pg_temp.fails(13, $q$approve_booking(pg_temp.id(101),pg_temp.v('b1'),5,gen_random_uuid())$q$, 'STALE_REVISION', 'expected revision enforced');
SELECT pg_temp.fails(13, $q$approve_booking(pg_temp.id(101),pg_temp.v('b1'),1,gen_random_uuid(),ARRAY['capacity'],'why')$q$, 'OVERRIDE_NOT_ALLOWED', 'staff holds no override');
SELECT pg_temp.exec(13, $q$approve_booking(pg_temp.id(101),pg_temp.v('b1'),1,gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'CONFIRMED'
  AND (SELECT occupied_places FROM public.sessions WHERE id = pg_temp.v('s1')) = 1 AND pg_temp.h(pg_temp.v('pkg')) = 1
  AND pg_temp.r('pkg') = 1, 'approval takes a place and a logical hold, no ledger debit');
SELECT pg_temp.ok((SELECT status = 'SCHEDULED' AND due_at = timestamptz '2031-01-05 10:00Z' FROM private.booking_reminders WHERE booking_id = pg_temp.v('b1')), 'reminder scheduled 24h before start');
SELECT pg_temp.fails(13, $q$approve_booking(pg_temp.id(101),pg_temp.v('b1'),2,gen_random_uuid())$q$, 'INVALID_STATE', 'double approval refused');
SELECT pg_temp.fails(3, $q$cancel_booking(pg_temp.id(101),pg_temp.v('b1'),2,'changed plans',gen_random_uuid())$q$, 'MEMBER_POLICY_UNRESOLVED', 'member cancel of CONFIRMED awaits D05');
SELECT pg_temp.fails(3, $q$reject_booking(pg_temp.id(101),pg_temp.v('b1'),2,'no',gen_random_uuid())$q$, 'MEMBER_REJECTION_DISABLED', 'member cannot reject own approved request');

-- The five overrides: exact permission, mandatory reason, recorded controls.
SELECT pg_temp.fails(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid())$q$, 'OFFER_INELIGIBLE', 'package from another offer series needs override');
SELECT pg_temp.fails(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid(),ARRAY['offer'],'same level')$q$, 'SESSION_FULL', 'capacity still enforced');
SELECT pg_temp.fails(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid(),ARRAY['offer','capacity'])$q$, 'REASON_REQUIRED', 'override needs a reason');
SELECT pg_temp.fails(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid(),ARRAY['session_state'],'x')$q$, 'INVALID_OVERRIDE', 'no session state override exists');
SELECT pg_temp.put('b2', pg_temp.run(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s1'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid(),ARRAY['offer','capacity','age'],'Coach request')$q$) ->> 'booking_id');
SELECT pg_temp.ok((pg_temp.booking('b2')).status = 'CONFIRMED' AND (pg_temp.booking('b2')).override_reason = 'Coach request'
  AND (SELECT occupied_places FROM public.sessions WHERE id = pg_temp.v('s1')) = 2
  AND (SELECT metadata -> 'overrides' = '["offer","capacity"]'::jsonb FROM private.booking_events WHERE booking_id = pg_temp.v('b2') AND event_type = 'OVERRIDE_USED'),
  'capacity exceeded with exact controls used recorded, unneeded flag not claimed');
-- D34: quota override without free credit records PENDING, never a credit.
SELECT pg_temp.fails(13, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s3'),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid())$q$, 'CREDIT_UNAVAILABLE', 'A = 0 refuses ordinary confirmation');
SELECT pg_temp.put('b3', pg_temp.run(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s3'),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid(),ARRAY['quota'],'Waiting renewal')$q$) ->> 'booking_id');
SELECT pg_temp.ok((pg_temp.booking('b3')).status = 'PENDING' AND pg_temp.h(pg_temp.v('pkg')) = 1 AND pg_temp.r('pkg') = 1
  AND (SELECT occupied_places FROM public.sessions WHERE id = pg_temp.v('s3')) = 0
  AND EXISTS (SELECT FROM private.booking_events WHERE booking_id = pg_temp.v('b3') AND event_type = 'OVERRIDE_USED' AND after_status = 'PENDING'),
  'D34: quota override yields PENDING with OVERRIDE_USED, H and R unchanged');
SELECT pg_temp.fails(12, $q$approve_booking(pg_temp.id(101),pg_temp.v('b3'),1,gen_random_uuid(),ARRAY['quota'],'force')$q$, 'CREDIT_UNAVAILABLE', 'quota override never confirms without credit');
SELECT pg_temp.ok((pg_temp.booking('b3')).status = 'PENDING' AND (pg_temp.booking('b3')).revision = 1, 'failed approval leaves booking untouched');
SELECT pg_temp.fails(3, $q$request_booking(pg_temp.id(101),pg_temp.v('s4'),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid())$q$, 'CREDIT_UNAVAILABLE', 'family request needs free credit');
SELECT pg_temp.exec(3, $q$cancel_booking(pg_temp.id(101),pg_temp.v('b3'),1,'not needed',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'CANCELLED'
  AND EXISTS (SELECT FROM private.notification_events WHERE booking_id = pg_temp.v('b3') AND event_type = 'BOOKING_CANCELLED'), 'family withdraws own PENDING');
SELECT pg_temp.put('b4', pg_temp.run(12, $q$request_booking(pg_temp.id(101),pg_temp.v('s5'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid())$q$) ->> 'booking_id');
SELECT pg_temp.fails(13, $q$reject_booking(pg_temp.id(101),pg_temp.v('b4'),1,NULL,gen_random_uuid())$q$, 'REASON_REQUIRED', 'rejection needs a reason');
SELECT pg_temp.exec(13, $q$reject_booking(pg_temp.id(101),pg_temp.v('b4'),1,'Group full',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'REJECTED', 'staff rejects PENDING');
SELECT pg_temp.put('b5', pg_temp.run(12, $q$request_booking(pg_temp.id(101),pg_temp.v('s5'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid())$q$) ->> 'booking_id');
SELECT pg_temp.ok(pg_temp.v('b5') <> pg_temp.v('b4'), 'terminal booking frees uniqueness; new UUID created');

-- Attendance and completion (D04, D29).
SELECT pg_temp.fails(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),true,2,gen_random_uuid())$q$, 'TOO_EARLY', 'no attendance before start');
UPDATE public.sessions SET starts_at = '2026-09-01 10:00Z', ends_at = '2026-09-01 11:00Z' WHERE id = pg_temp.v('s1'); -- time passes
SELECT pg_temp.fails(2, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),true,2,gen_random_uuid())$q$, 'NOT_FOUND', 'coach of another session sees nothing');
SELECT pg_temp.fails(13, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),true,2,gen_random_uuid())$q$, 'FORBIDDEN', 'staff cannot record attendance');
SELECT pg_temp.exec(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),true,2,gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'COMPLETED'
  AND pg_temp.r('pkg') = 0 AND pg_temp.h(pg_temp.v('pkg')) = 0
  AND (SELECT status FROM public.player_packages WHERE id = pg_temp.v('pkg')) = 'EXHAUSTED'
  AND (SELECT occupied_places FROM public.sessions WHERE id = pg_temp.v('s1')) = 2, 'PRESENT consumes the reserved credit although A = 0');
SELECT pg_temp.exec(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),true,2,gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'NO_CHANGE'
  AND (SELECT count(*) = 1 FROM private.course_ledger WHERE booking_id = pg_temp.v('b1')), 'same observation with new key: NO_CHANGE, single debit');
SELECT pg_temp.fails(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),false,3,gen_random_uuid())$q$, 'REASON_REQUIRED', 'correction needs a reason');
SELECT pg_temp.exec(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),false,3,gen_random_uuid(),'Was sick')$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'ATTENDANCE_CORRECTED'
  AND pg_temp.r('pkg') = 1 AND (SELECT status FROM public.player_packages WHERE id = pg_temp.v('pkg')) = 'ACTIVE'
  AND (SELECT count(*) = 1 FROM private.course_ledger c JOIN private.course_ledger d ON d.id = c.reverses_entry_id
    WHERE c.booking_id = pg_temp.v('b1') AND c.reason = 'ATTENDANCE_CORRECTION' AND d.reason = 'SESSION_CONSUMED'), 'PRESENT to ABSENT compensates the exact debit once');
SELECT pg_temp.put('b6', pg_temp.run(13, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s4'),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid())$q$) ->> 'booking_id');
SELECT pg_temp.fails(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b1'),true,4,gen_random_uuid(),'Mistake')$q$, 'CREDIT_UNAVAILABLE', 'ABSENT to PRESENT never takes another booking hold');
SELECT pg_temp.fails(12, $q$complete_booking(pg_temp.id(101),pg_temp.v('b6'),1,'Done',gen_random_uuid())$q$, 'COMPLETION_BEFORE_START_UNRESOLVED', 'early admin completion awaits D29');
UPDATE public.sessions SET starts_at = '2026-09-02 10:00Z', ends_at = '2026-09-02 11:00Z' WHERE id = pg_temp.v('s4'); -- time passes
SELECT pg_temp.exec(12, $q$complete_booking(pg_temp.id(101),pg_temp.v('b6'),1,'Coach absent from app',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'COMPLETED'
  AND (pg_temp.booking('b6')).completion_source = 'ADMIN' AND pg_temp.r('pkg') = 0
  AND NOT EXISTS (SELECT FROM public.booking_attendance WHERE booking_id = pg_temp.v('b6')), 'admin completion consumes without fabricating presence');
SELECT pg_temp.exec(1, $q$record_attendance(pg_temp.id(101),pg_temp.v('b6'),true,2,gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'ATTENDANCE_RECORDED'
  AND (SELECT count(*) = 1 FROM private.course_ledger WHERE booking_id = pg_temp.v('b6')), 'later PRESENT observation does not debit again');
SELECT pg_temp.ok((SELECT remaining_sessions = (SELECT sum(delta) FROM private.course_ledger l WHERE l.package_id = k.id) FROM public.player_packages k WHERE id = pg_temp.v('pkg'))
  AND NOT EXISTS (SELECT FROM public.bookings b WHERE b.package_id = pg_temp.v('pkg') AND private.booking_net_consumed(b.academy_id, b.package_id, b.id) NOT IN (0,1)),
  'ledger sum equals R and net consumption per booking is 0 or 1');

-- Evaluations.
SELECT pg_temp.put('e1', pg_temp.run(1, $q$record_evaluation(pg_temp.id(101),pg_temp.v('b6'),4,3,5,4,gen_random_uuid(),'Good footwork')$q$) ->> 'evaluation_id');
SELECT pg_temp.fails(1, $q$record_evaluation(pg_temp.id(101),pg_temp.v('b6'),4,3,5,4,gen_random_uuid())$q$, 'ALREADY_EVALUATED', 'one evaluation per booking');
SELECT pg_temp.fails(1, $q$record_evaluation(pg_temp.id(101),pg_temp.v('b1'),4,3,5,4,gen_random_uuid())$q$, 'PLAYER_ABSENT', 'absent player cannot be evaluated');
SELECT pg_temp.fails(2, $q$record_evaluation(pg_temp.id(101),pg_temp.v('b6'),4,3,5,4,gen_random_uuid())$q$, 'NOT_FOUND', 'unassigned coach cannot evaluate');
SELECT pg_temp.fails(12, $q$record_evaluation(pg_temp.id(101),pg_temp.v('b2'),4,3,5,4,gen_random_uuid())$q$, 'FORBIDDEN', 'manager has correction only');
SELECT pg_temp.fails(1, $q$record_evaluation(pg_temp.id(101),pg_temp.v('b6'),6,3,5,4,gen_random_uuid())$q$, 'INVALID_INPUT', 'scores bounded 1..5');
SELECT pg_temp.exec(12, $q$correct_evaluation(pg_temp.id(101),pg_temp.v('e1'),3,3,5,4,1,'Typo',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'revision' = '2', 'manager corrects with revision');
SELECT pg_temp.fails(12, $q$correct_evaluation(pg_temp.id(101),pg_temp.v('e1'),3,3,5,4,1,'Again',gen_random_uuid())$q$, 'STALE_REVISION', 'stale correction refused');

-- Archive (D31) keeps places and credits; an active booking is cancelled first.
SELECT pg_temp.exec(13, $q$archive_booking(pg_temp.id(101),pg_temp.v('b6'),3,'Cleanup',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'ARCHIVED'
  AND (pg_temp.booking('b6')).status = 'COMPLETED' AND (pg_temp.booking('b6')).deleted_at IS NOT NULL
  AND pg_temp.r('pkg') = 0 AND (SELECT occupied_places FROM public.sessions WHERE id = pg_temp.v('s4')) = 1, 'archiving COMPLETED changes neither place nor credit');
SELECT pg_temp.fails(13, $q$archive_booking(pg_temp.id(101),pg_temp.v('b6'),4,'Again',gen_random_uuid())$q$, 'INVALID_STATE', 'archive once');
SELECT pg_temp.exec(13, $q$archive_booking(pg_temp.id(101),pg_temp.v('b5'),1,'Duplicate',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'CANCELLED'
  AND EXISTS (SELECT FROM private.booking_events WHERE booking_id = pg_temp.v('b5') AND event_type = 'CANCELLED'), 'active booking cancelled before archive');

-- Session cancellation: all-or-nothing batch.
SELECT pg_temp.exec(12, $q$update_player_identity(pg_temp.id(101),pg_temp.id(302),gen_random_uuid(),NULL,NULL,'2000-01-01')$q$);
SELECT pg_temp.fails(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s6'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid())$q$, 'AGE_INELIGIBLE', 'age computed at session date');
SELECT pg_temp.exec(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s6'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid(),ARRAY['age'],'Adult trial')$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'CONFIRMED', 'age override with reason');

SELECT pg_temp.put('b7', pg_temp.run(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s5'),pg_temp.id(302),pg_temp.id(802),gen_random_uuid(),ARRAY['age'],'Adult')$q$) ->> 'booking_id');
SELECT pg_temp.put('b8', pg_temp.run(13, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s5'),pg_temp.id(301),pg_temp.id(801),gen_random_uuid())$q$) ->> 'booking_id');
INSERT INTO private.course_ledger (academy_id, operation_id, effect_key, actor_kind, actor_ref, package_id, booking_id, delta, reason, occurred_at)
SELECT b.academy_id, pg_temp.id(1601), 'legacy-debit', 'SYSTEM', 'legacy-fixture', b.package_id, b.id, -1, 'SESSION_CONSUMED', now()
FROM public.bookings b WHERE b.id = greatest(pg_temp.v('b7'), pg_temp.v('b8')); -- unresolved legacy state
SELECT pg_temp.fails(12, $q$cancel_session(pg_temp.id(101),pg_temp.v('s5'),1,'Rain',gen_random_uuid())$q$, 'LEGACY_CREDIT_UNRESOLVED', 'unresolved debit blocks the batch');
SELECT pg_temp.ok((pg_temp.booking('b7')).status = 'CONFIRMED' AND (pg_temp.booking('b8')).status = 'CONFIRMED'
  AND (SELECT status = 'OPEN' AND occupied_places = 2 FROM public.sessions WHERE id = pg_temp.v('s5'))
  AND NOT EXISTS (SELECT FROM private.booking_events WHERE booking_id IN (pg_temp.v('b7'), pg_temp.v('b8')) AND event_type = 'CANCELLED'), 'failed batch rolled back entirely');
SELECT pg_temp.put('b9', pg_temp.run(12, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s2'),pg_temp.id(301),pg_temp.id(801),gen_random_uuid(),ARRAY['offer'],'Swap')$q$) ->> 'booking_id');
SELECT pg_temp.exec(12, $q$cancel_session(pg_temp.id(101),pg_temp.v('s2'),1,'Court repair',gen_random_uuid())$q$);
SELECT pg_temp.ok((pg_temp.last() ->> 'bookings_cancelled')::integer = 1
  AND (pg_temp.booking('b9')).status = 'CANCELLED' AND (SELECT status = 'CANCELLED' AND occupied_places = 0 FROM public.sessions WHERE id = pg_temp.v('s2'))
  AND (SELECT status FROM private.booking_reminders WHERE booking_id = pg_temp.v('b9')) = 'CANCELLED', 'session cancel releases bookings and reminders');
SELECT pg_temp.exec(12, $q$create_session(pg_temp.id(101),pg_temp.v('offer'),pg_temp.id(401),'2031-01-06 11:00Z','2031-01-06 12:00Z',1,gen_random_uuid(),NULL,pg_temp.v('court'))$q$);
SELECT pg_temp.ok(pg_temp.last() ? 'session_id', 'CANCELLED session no longer blocks court and coach');

-- Players and family links.
SELECT pg_temp.put('kid', pg_temp.run(3, $q$create_player(pg_temp.id(101),'Kid','New',gen_random_uuid(),'2018-05-01')$q$) ->> 'player_id');
SELECT pg_temp.ok(EXISTS (SELECT FROM public.player_links WHERE player_id = pg_temp.v('kid') AND user_id = pg_temp.id(3) AND relationship = 'GUARDIAN')
  AND pg_temp.visible(3, 'public.players') = 2, 'parent-created child is linked to that parent only');
SELECT pg_temp.fails(13, $q$create_player(pg_temp.id(101),'No','Access',gen_random_uuid())$q$, 'FORBIDDEN', 'staff cannot create players');
SELECT pg_temp.fails(3, $q$update_player_identity(pg_temp.id(101),pg_temp.id(302),gen_random_uuid(),'X')$q$, 'NOT_FOUND', 'parent cannot edit another child');
SELECT pg_temp.fails(3, $q$update_player_identity(pg_temp.id(101),pg_temp.v('kid'),gen_random_uuid(),NULL,NULL,NULL,NULL,NULL,pg_temp.id(2401))$q$, 'FORBIDDEN', 'parent cannot set community');
SELECT pg_temp.exec(3, $q$update_player_identity(pg_temp.id(101),pg_temp.v('kid'),gen_random_uuid(),'Kiddo')$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'UPDATED'
  AND NOT (SELECT metadata::text LIKE '%Kiddo%' FROM private.audit_log WHERE action = 'player.identity_updated' AND resource_id = pg_temp.v('kid')), 'identity update audited without personal values');
SELECT pg_temp.fails(12, $q$archive_player(pg_temp.id(101),pg_temp.id(302),'Left',gen_random_uuid())$q$, 'PLAYER_IN_USE', 'player with active booking not archived');
SELECT pg_temp.fails(12, $q$assign_player_link(pg_temp.id(101),pg_temp.id(301),pg_temp.id(12),'SELF',gen_random_uuid())$q$, 'SELF_ALREADY_LINKED', 'one active SELF');
SELECT pg_temp.fails(12, $q$assign_player_link(pg_temp.id(101),pg_temp.id(301),pg_temp.id(3),'GUARDIAN',gen_random_uuid())$q$, 'ACTIVE_LINK_EXISTS', 'one active link per pair');
SELECT pg_temp.fails(12, $q$assign_player_link(pg_temp.id(101),pg_temp.id(301),pg_temp.id(17),'GUARDIAN',gen_random_uuid())$q$, 'NOT_FOUND', 'link requires local active membership');
SELECT pg_temp.exec(12, $q$assign_player_link(pg_temp.id(101),pg_temp.id(302),pg_temp.id(4),'GUARDIAN',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ? 'link_id', 'several guardians allowed');
SELECT pg_temp.fails(12, $q$set_player_contacts(pg_temp.id(101),pg_temp.id(301),pg_temp.id(1105),NULL,gen_random_uuid())$q$, 'INVALID_LINK', 'contact must be an active link of the player');
SELECT pg_temp.exec(12, $q$set_player_contacts(pg_temp.id(101),pg_temp.id(301),pg_temp.id(1102),pg_temp.id(1101),gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'UPDATED'
  AND (SELECT is_primary AND NOT is_financial_contact FROM public.player_links WHERE id = pg_temp.id(1102))
  AND (SELECT NOT is_primary AND is_financial_contact FROM public.player_links WHERE id = pg_temp.id(1101)), 'primary and financial contacts swapped atomically');
SELECT pg_temp.exec(12, $q$revoke_player_link(pg_temp.id(101),pg_temp.id(1102),'Custody change',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'REVOKED'
  AND (SELECT count(*) FROM public.player_links WHERE player_id = pg_temp.id(301) AND revoked_at IS NULL AND is_primary) = 0
  AND (pg_temp.query_as(4, 'SELECT to_jsonb(count(*)) FROM public.players WHERE id = pg_temp.id(301)') #>> '{}')::integer = 0, 'revocation removes access and designates no successor');

-- Memberships and roles.
SELECT pg_temp.fails(11, $q$set_membership_roles(pg_temp.id(101),pg_temp.id(211),ARRAY['ACADEMY_ADMIN','MANAGER'],'more',gen_random_uuid())$q$, 'SELF_ACTION_FORBIDDEN', 'no self escalation');
SELECT pg_temp.fails(11, $q$set_membership_roles(pg_temp.id(101),pg_temp.id(213),ARRAY['ACADEMY_OWNER'],'promote',gen_random_uuid())$q$, 'FORBIDDEN', 'admin cannot grant OWNER');
SELECT pg_temp.fails(12, $q$set_membership_roles(pg_temp.id(101),pg_temp.id(213),ARRAY['STAFF','COACH'],'x',gen_random_uuid())$q$, 'FORBIDDEN', 'manager cannot manage roles');
SELECT pg_temp.fails(11, $q$set_membership_roles(pg_temp.id(101),pg_temp.id(213),ARRAY['CUSTOM'],'x',gen_random_uuid())$q$, 'INVALID_ROLE', 'only fixed roles');
SELECT pg_temp.exec(11, $q$set_membership_roles(pg_temp.id(101),pg_temp.id(213),ARRAY['STAFF','COACH'],'Also coaches',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() -> 'roles' = '["COACH","STAFF"]'::jsonb, 'fixed roles set and audited');
SELECT pg_temp.exec(11, $q$set_membership_roles(pg_temp.id(101),pg_temp.id(213),ARRAY['COACH','STAFF'],'Same',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'NO_CHANGE', 'same role set is NO_CHANGE');
SELECT pg_temp.fails(11, $q$invite_member(pg_temp.id(101),'boss@example.test',ARRAY['ACADEMY_OWNER'],now()+interval '7 days',gen_random_uuid())$q$, 'FORBIDDEN', 'admin cannot invite an owner');
SELECT pg_temp.fails(11, $q$invite_member(pg_temp.id(101),'late@example.test',ARRAY['COACH'],now()+interval '60 days',gen_random_uuid())$q$, 'INVALID_INPUT', 'invitation expiry bounded');
SELECT pg_temp.exec(11, $q$invite_member(pg_temp.id(101),' New.Coach@Example.test ',ARRAY['COACH'],now()+interval '7 days',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ? 'invitation_id'
  AND EXISTS (SELECT FROM private.academy_invitations i JOIN private.notification_events n ON n.invitation_id = i.id
    WHERE i.email = 'new.coach@example.test' AND n.event_type = 'MEMBERSHIP_INVITED' AND NOT n.snapshot::text LIKE '%@%'), 'invitation normalized, queued without email in snapshot');
SELECT pg_temp.fails(11, $q$invite_member(pg_temp.id(101),'new.coach@example.test',ARRAY['STAFF'],now()+interval '7 days',gen_random_uuid())$q$, 'INVITATION_EXISTS', 'one active invitation per email');
SELECT pg_temp.fails(11, $q$suspend_membership(pg_temp.id(101),pg_temp.id(210),'x',gen_random_uuid())$q$, 'FORBIDDEN', 'admin cannot suspend an owner');
SELECT pg_temp.exec(11, $q$suspend_membership(pg_temp.id(101),pg_temp.id(213),'Leave',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'SUSPENDED', 'admin suspends staff');
SELECT pg_temp.fails(13, $q$schedule_booking(pg_temp.id(101),pg_temp.v('s6'),pg_temp.id(301),pg_temp.id(801),gen_random_uuid())$q$, 'FORBIDDEN', 'suspended member loses commands immediately');
SELECT pg_temp.exec(11, $q$reactivate_membership(pg_temp.id(101),pg_temp.id(213),'Back',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'REACTIVATED', 'membership reactivated');
SELECT pg_temp.fails(18, $q$create_stadium(pg_temp.id(101),'X','Y',gen_random_uuid())$q$, 'Authentication required or account unavailable', 'suspended profile rejected');
SELECT pg_temp.fails(17, $q$create_stadium(pg_temp.id(101),'X','Y',gen_random_uuid())$q$, 'FORBIDDEN', 'outsider rejected');

-- Cross-tenant: forged academy or UUID never reaches another tenant.
SELECT pg_temp.fails(8, $q$approve_booking(pg_temp.id(102),pg_temp.v('b5'),1,gen_random_uuid())$q$, 'NOT_FOUND', 'booking of A invisible under B');
SELECT pg_temp.fails(8, $q$approve_booking(pg_temp.id(101),pg_temp.v('b5'),1,gen_random_uuid())$q$, 'FORBIDDEN', 'owner of B has no role in A');
SELECT pg_temp.fails(10, $q$schedule_booking(pg_temp.id(101),pg_temp.id(903),pg_temp.id(301),pg_temp.v('pkg'),gen_random_uuid())$q$, 'NOT_FOUND', 'session of B cannot be booked from A');
SELECT pg_temp.fails(10, $q$record_payment(pg_temp.id(101),pg_temp.id(303),NULL,'10','XAF','CASH',gen_random_uuid())$q$, 'NOT_FOUND', 'payment cannot target a player of B');

-- Platform versus tenant.
SELECT pg_temp.fails(10, $q$create_academy('X','Douala','CM','Africa/Douala','FR','o@example.test',now()+interval '7 days',gen_random_uuid())$q$, 'FORBIDDEN', 'tenant owner cannot create academies');
SELECT pg_temp.fails(15, $q$create_academy('X','Douala','CM','Mars/Base','FR','o@example.test',now()+interval '7 days',gen_random_uuid())$q$, 'INVALID_INPUT', 'timezone validated');
SELECT pg_temp.put('academy_c', pg_temp.run(15, $q$create_academy('Academy C','Yaounde','CM','Africa/Douala','FR','owner.c@example.test',now()+interval '7 days',gen_random_uuid())$q$) ->> 'academy_id');
SELECT pg_temp.ok((SELECT scope = 'TENANT' AND academy_id = pg_temp.v('academy_c') FROM private.command_receipts WHERE rpc_name = 'create_academy')
  AND EXISTS (SELECT FROM private.academy_invitations WHERE academy_id = pg_temp.v('academy_c') AND requested_role_codes = ARRAY['ACADEMY_OWNER']), 'academy and first-owner invitation in one tenant operation');
SELECT pg_temp.fails(15, $q$update_academy(pg_temp.id(101),gen_random_uuid(),'Renamed')$q$, 'FORBIDDEN', 'platform admin cannot edit tenant settings');
SELECT pg_temp.fails(15, $q$create_plan('TEST-A',1,'Dup',gen_random_uuid())$q$, 'PLAN_EXISTS', 'plan code/version unique');
SELECT pg_temp.fails(15, $q$create_subscription(pg_temp.id(101),pg_temp.id(2601),'ACTIVE',now(),'x',gen_random_uuid())$q$, 'SUBSCRIPTION_EXISTS', 'one current subscription');
SELECT pg_temp.exec(15, $q$transition_subscription(pg_temp.id(101),pg_temp.id(2701),'SUSPENDED',1,'Unpaid',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'revision' = '2'
  AND EXISTS (SELECT FROM private.subscription_events WHERE subscription_id = pg_temp.id(2701) AND event_type = 'SUSPENDED' AND before_status = 'ACTIVE'), 'subscription transition journaled');
SELECT pg_temp.fails(15, $q$transition_subscription(pg_temp.id(101),pg_temp.id(2701),'TRIALING',2,'x',gen_random_uuid())$q$, 'INVALID_STATE', 'no return to trial');
SELECT pg_temp.fails(11, $q$transition_subscription(pg_temp.id(101),pg_temp.id(2701),'ACTIVE',2,'x',gen_random_uuid())$q$, 'FORBIDDEN', 'tenant cannot change its subscription');
SELECT pg_temp.exec(15, $q$set_academy_status(pg_temp.id(102),'SUSPENDED','Review',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'status' = 'SUSPENDED', 'platform suspends academy B');
SELECT pg_temp.fails(8, $q$create_stadium(pg_temp.id(102),'X','Y',gen_random_uuid())$q$, 'FORBIDDEN', 'suspended academy blocks its owner');

-- Ownership transfer: the previous owner loses owner rights in the same transaction.
SELECT pg_temp.exec(10, $q$transfer_ownership(pg_temp.id(101),pg_temp.id(211),'Handover',gen_random_uuid())$q$);
SELECT pg_temp.ok(pg_temp.last() ->> 'outcome' = 'TRANSFERRED'
  AND private.has_local_role(pg_temp.id(101), 'ACADEMY_OWNER') IS NOT NULL
  AND EXISTS (SELECT FROM private.academy_membership_roles WHERE membership_id = pg_temp.id(211) AND role_code = 'ACADEMY_OWNER' AND revoked_at IS NULL)
  AND NOT EXISTS (SELECT FROM private.academy_membership_roles WHERE membership_id = pg_temp.id(210) AND role_code = 'ACADEMY_OWNER' AND revoked_at IS NULL), 'ownership transferred');
SELECT pg_temp.fails(10, $q$create_stadium(pg_temp.id(101),'X','Y',gen_random_uuid())$q$, 'FORBIDDEN', 'former owner keeps no implicit right');

SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ok(true, 'every effect references a receipt of the same tenant scope (deferred checks passed)');

SELECT '1..' || currval('pg_temp.assertion_number');
ROLLBACK;
