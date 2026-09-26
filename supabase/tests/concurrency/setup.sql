-- Committed fixtures for the two-connection concurrency scenarios. Loaded only
-- into the disposable `conc` database created by scripts/test-database.mjs.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir ../database/support/helpers.sql
\ir ../database/support/security_helpers.sql
\ir ../database/support/security_fixtures.sql
SET CONSTRAINTS ALL DEFERRED;

CREATE SCHEMA conc;
CREATE TABLE conc.vars (k text PRIMARY KEY, v uuid NOT NULL);
CREATE FUNCTION pg_temp.keep(p_key text, p_user integer, p_call text, p_field text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO conc.vars VALUES (p_key, (pg_temp.query_as(p_user, 'SELECT public.' || p_call) ->> p_field)::uuid);
$$;
CREATE FUNCTION pg_temp.v(p_key text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM conc.vars WHERE k = p_key; $$;
CREATE FUNCTION pg_temp.session(p_key text, p_coach integer, p_starts timestamptz, p_capacity integer) RETURNS void LANGUAGE sql AS $$
  SELECT pg_temp.keep(p_key, 12, format('create_session(%L,%L,%L,%L,%L,%s,gen_random_uuid())', pg_temp.id(101), pg_temp.id(701),
    pg_temp.id(p_coach), p_starts, p_starts + interval '1 hour', p_capacity), 'session_id');
$$;

SELECT pg_temp.session('sa', 401, '2031-03-01 10:00Z', 5);
SELECT pg_temp.session('sb', 401, '2031-03-02 10:00Z', 5);
SELECT pg_temp.session('sc', 402, '2031-03-03 10:00Z', 1);
SELECT pg_temp.session('sd', 402, '2031-03-04 10:00Z', 5);
SELECT pg_temp.session('se', 402, '2031-03-05 10:00Z', 5);
SELECT pg_temp.session('sf', 402, '2031-03-06 10:00Z', 5);
SELECT pg_temp.session('sg', 402, '2031-03-07 10:00Z', 5);

-- Package k1 for player 301 with exactly one free credit (R = 1, H = 0).
SELECT pg_temp.keep('k1', 10, format('purchase_package(%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.id(301), pg_temp.id(701)), 'package_id');
SELECT pg_temp.keep('pay', 10, format('record_payment(%L,%L,%L,''100'',''XAF'',''CASH'',gen_random_uuid())', pg_temp.id(101), pg_temp.id(301), pg_temp.v('k1')), 'payment_id');
SELECT pg_temp.query_as(10, format('SELECT public.confirm_payment(%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('pay')));
SELECT pg_temp.query_as(10, format('SELECT public.activate_package_credit(%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('k1')));
SELECT pg_temp.query_as(10, format('SELECT public.adjust_course_credit(%L,%L,-9,''one credit left'',gen_random_uuid())', pg_temp.id(101), pg_temp.v('k1')));

-- Last credit: two PENDING requests on the same package (PENDING holds nothing).
SELECT pg_temp.keep('ra', 3, format('request_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('sa'), pg_temp.id(301), pg_temp.v('k1')), 'booking_id');
SELECT pg_temp.keep('rb', 3, format('request_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('sb'), pg_temp.id(301), pg_temp.v('k1')), 'booking_id');
-- Last place: two players PENDING on a session of capacity 1.
SELECT pg_temp.keep('pc1', 12, format('request_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('sc'), pg_temp.id(301), pg_temp.id(801)), 'booking_id');
SELECT pg_temp.keep('pc2', 12, format('request_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('sc'), pg_temp.id(302), pg_temp.id(802)), 'booking_id');
-- Double approval.
SELECT pg_temp.keep('pd', 12, format('request_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('sd'), pg_temp.id(302), pg_temp.id(802)), 'booking_id');
-- Cancel versus attendance, and double compensation, on sessions that already started.
SELECT pg_temp.keep('ce', 12, format('schedule_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('se'), pg_temp.id(302), pg_temp.id(802)), 'booking_id');
SELECT pg_temp.keep('cg', 12, format('schedule_booking(%L,%L,%L,%L,gen_random_uuid())', pg_temp.id(101), pg_temp.v('sg'), pg_temp.id(302), pg_temp.id(802)), 'booking_id');
UPDATE public.sessions SET starts_at = starts_at - interval '5 years', ends_at = ends_at - interval '5 years'
  WHERE id IN (pg_temp.v('se'), pg_temp.v('sg')); -- time passes
SELECT pg_temp.query_as(2, format('SELECT public.record_attendance(%L,%L,true,1,gen_random_uuid())', pg_temp.id(101), pg_temp.v('cg')));

-- 3D committed invitations and an in-flight delivery for real two-session races.
UPDATE private.academy_invitations SET status='REVOKED';
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
(pg_temp.id(60),'race60@example.test',clock_timestamp()),(pg_temp.id(61),'race61@example.test',clock_timestamp()),
(pg_temp.id(62),'race62@example.test',clock_timestamp());
SELECT pg_temp.keep('invite60',10,format('invite_member(%L,''race60@example.test'',ARRAY[''PARENT''],clock_timestamp()+interval ''1 day'',gen_random_uuid())',pg_temp.id(101)),'invitation_id');
SELECT pg_temp.keep('invite61',10,format('invite_member(%L,''race61@example.test'',ARRAY[''PARENT''],clock_timestamp()+interval ''1 day'',gen_random_uuid())',pg_temp.id(101)),'invitation_id');
SELECT pg_temp.keep('invite62',10,format('invite_member(%L,''race62@example.test'',ARRAY[''PARENT''],clock_timestamp()+interval ''1 day'',gen_random_uuid())',pg_temp.id(101)),'invitation_id');
-- Isolate acceptance races from external Auth provisioning (tested separately).
UPDATE private.academy_invitations SET status='SENT',token_digest=encode(sha256(convert_to(repeat('e',64),'UTF8')),'hex') WHERE id=pg_temp.v('invite60');
UPDATE private.academy_invitations SET status='SENT',token_digest=encode(sha256(convert_to(repeat('f',64),'UTF8')),'hex') WHERE id=pg_temp.v('invite61');
UPDATE private.academy_invitations SET status='SENT',token_digest=encode(sha256(convert_to(repeat('g',64),'UTF8')),'hex') WHERE id=pg_temp.v('invite62');
UPDATE private.notification_deliveries SET status='SENDING',attempts=1,lease_token=pg_temp.id(96001),
 lease_until=x.t,next_attempt_at=x.t FROM (SELECT clock_timestamp()+interval '120 seconds' AS t) x
 WHERE id=pg_temp.id(1801);
COMMIT;
