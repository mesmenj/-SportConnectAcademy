-- Phase 3C booking engine (V1.1 §6 and §11.1, D30, D34 decided: a quota override
-- without free credit records PENDING, never a fictitious credit). Lock order is
-- player -> session -> package -> booking; A = R - H is recounted after locking.
-- Open decisions are refused explicitly: D05 (member cancel/reject of CONFIRMED)
-- -> MEMBER_POLICY_UNRESOLVED, D29 (admin completion before start)
-- -> COMPLETION_BEFORE_START_UNRESOLVED.

CREATE FUNCTION private.lock_booking_graph(p_academy uuid, p_player uuid, p_session uuid, p_package uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  PERFORM 1 FROM public.players WHERE academy_id = p_academy AND id = p_player FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM 1 FROM public.sessions WHERE academy_id = p_academy AND id = p_session FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF p_package IS NOT NULL THEN
    PERFORM 1 FROM public.player_packages WHERE academy_id = p_academy AND id = p_package
      AND player_id = p_player FOR UPDATE;
    IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  END IF;
END;
$$;

-- Reads immutable ids, locks the graph, then locks and returns the booking.
CREATE FUNCTION private.lock_booking(p_academy uuid, p_booking uuid) RETURNS public.bookings
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE b public.bookings;
BEGIN
  SELECT * INTO b FROM public.bookings WHERE academy_id = p_academy AND id = p_booking;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.lock_booking_graph(p_academy, b.player_id, b.session_id, b.package_id);
  SELECT * INTO b FROM public.bookings WHERE academy_id = p_academy AND id = p_booking FOR UPDATE;
  RETURN b;
END;
$$;

CREATE FUNCTION private.check_revision(p_actual bigint, p_expected bigint) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF p_expected IS NULL OR p_actual <> p_expected THEN PERFORM private.fail('STALE_REVISION'); END IF;
END;
$$;

CREATE FUNCTION private.violation_code(p_control text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
  SELECT CASE p_control WHEN 'offer' THEN 'OFFER_INELIGIBLE' WHEN 'age' THEN 'AGE_INELIGIBLE'
    WHEN 'player_overlap' THEN 'PLAYER_CONFLICT' WHEN 'capacity' THEN 'SESSION_FULL'
    WHEN 'quota' THEN 'CREDIT_UNAVAILABLE' END;
$$;

-- Each requested override needs its exact permission, every call. Returns the
-- trimmed reason, mandatory as soon as one override is requested.
CREATE FUNCTION private.check_overrides(p_academy uuid, p_overrides text[], p_reason text) RETURNS text
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE o text;
BEGIN
  IF array_position(p_overrides, NULL) IS NOT NULL
     OR NOT p_overrides <@ ARRAY['capacity','age','offer','quota','player_overlap'] THEN
    PERFORM private.fail('INVALID_OVERRIDE', '22023');
  END IF;
  FOREACH o IN ARRAY p_overrides LOOP
    IF NOT private.local_permission(p_academy, 'bookings.override.' || o) THEN
      PERFORM private.fail('OVERRIDE_NOT_ALLOWED', '42501');
    END IF;
  END LOOP;
  RETURN private.reason(p_reason, cardinality(p_overrides) > 0);
END;
$$;

-- Non-derogable checks raise; derogable ones are returned as violations, in a
-- fixed order. Caller holds the graph locks. p_booking excludes itself.
CREATE FUNCTION private.evaluate_booking(p_academy uuid, p_session uuid, p_player uuid, p_package uuid, p_booking uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  s public.sessions; p public.players; k public.player_packages;
  so public.service_offers; ko public.service_offers;
  v_age integer; v_h integer; v jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO s FROM public.sessions WHERE academy_id = p_academy AND id = p_session;
  IF s.status <> 'OPEN' THEN PERFORM private.fail('SESSION_CLOSED'); END IF;
  IF s.starts_at <= transaction_timestamp() THEN PERFORM private.fail('SESSION_STARTED'); END IF;
  SELECT * INTO p FROM public.players WHERE academy_id = p_academy AND id = p_player;
  IF p.deleted_at IS NOT NULL OR p.status <> 'ACTIVE' THEN PERFORM private.fail('PLAYER_INACTIVE'); END IF;
  IF p_package IS NULL THEN PERFORM private.fail('PACKAGE_REQUIRED', '22023'); END IF;
  SELECT * INTO k FROM public.player_packages WHERE academy_id = p_academy AND id = p_package;
  IF k.status NOT IN ('ACTIVE','EXHAUSTED') THEN PERFORM private.fail('PACKAGE_INACTIVE'); END IF;
  IF EXISTS (SELECT 1 FROM public.bookings b WHERE b.session_id = p_session AND b.player_id = p_player
      AND b.status IN ('PENDING','CONFIRMED') AND b.id IS DISTINCT FROM p_booking) THEN
    PERFORM private.fail('DUPLICATE_ACTIVE_BOOKING');
  END IF;
  SELECT * INTO so FROM public.service_offers WHERE academy_id = p_academy AND id = s.service_offer_id;
  SELECT * INTO ko FROM public.service_offers WHERE academy_id = p_academy AND id = k.service_offer_id;
  -- Activity and session type are never derogable; another series of the same
  -- activity/type needs bookings.override.offer.
  IF so.activity <> ko.activity OR so.session_type <> ko.session_type THEN
    PERFORM private.fail('OFFER_INCOMPATIBLE');
  END IF;
  IF so.offer_key <> ko.offer_key THEN v := v || '["offer"]'; END IF;
  v_age := CASE
    WHEN p.birth_date IS NOT NULL THEN extract(year FROM age(
      (s.starts_at AT TIME ZONE (SELECT a.timezone FROM public.academies a WHERE a.id = p_academy))::date,
      p.birth_date))::integer
    WHEN p.reported_age IS NOT NULL THEN p.reported_age + extract(year FROM age(s.starts_at, p.age_recorded_at))::integer
  END;
  IF v_age IS NULL OR v_age < so.min_age OR v_age > so.max_age THEN v := v || '["age"]'; END IF;
  IF EXISTS (SELECT 1 FROM public.bookings b JOIN public.sessions o ON o.academy_id = b.academy_id AND o.id = b.session_id
      WHERE b.academy_id = p_academy AND b.player_id = p_player AND b.status IN ('PENDING','CONFIRMED')
        AND b.session_id <> p_session AND o.status <> 'CANCELLED'
        AND tstzrange(o.starts_at, o.ends_at, '[)') && tstzrange(s.starts_at, s.ends_at, '[)')) THEN
    v := v || '["player_overlap"]';
  END IF;
  IF s.occupied_places >= s.capacity THEN v := v || '["capacity"]'; END IF;
  v_h := private.package_hold(p_academy, p_package);
  IF k.remaining_sessions - v_h < 1 THEN v := v || '["quota"]'; END IF;
  RETURN jsonb_build_object('violations', v, 'r', k.remaining_sessions, 'h', v_h,
    'a', k.remaining_sessions - v_h, 'starts_at', s.starts_at, 'session_offer_id', s.service_offer_id,
    'currency', k.currency, 'amount', CASE WHEN ko.price_basis = 'SESSION' THEN ko.price ELSE 0 END::text,
    'contract', jsonb_build_object('package_id', k.id, 'package_offer_id', ko.id, 'offer_key', ko.offer_key,
      'offer_version', ko.version, 'price_basis', ko.price_basis, 'unit_price', ko.price::text,
      'total_price', k.total_price::text, 'currency', k.currency, 'purchased_sessions', k.purchased_sessions,
      'session_offer_id', so.id));
END;
$$;

CREATE FUNCTION private.uncovered(p_violations jsonb, p_overrides text[]) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
  SELECT x FROM jsonb_array_elements_text(p_violations) WITH ORDINALITY AS t(x, n)
  WHERE x <> ALL (p_overrides) ORDER BY n LIMIT 1;
$$;

CREATE FUNCTION private.used_overrides(p_violations jsonb, p_overrides text[]) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY n), '[]'::jsonb)
  FROM jsonb_array_elements_text(p_violations) WITH ORDINALITY AS t(x, n) WHERE x = ANY (p_overrides);
$$;

CREATE FUNCTION private.insert_booking(p_ctx jsonb, p_session uuid, p_player uuid, p_package uuid,
  p_status text, p_ev jsonb, p_note text, p_course uuid, p_owner uuid, p_override_reason text) RETURNS uuid
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  v_academy uuid := (p_ctx ->> 'academy_id')::uuid;
  v_id uuid;
BEGIN
  IF length(p_note) > 500 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  IF p_course IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.community_courses c WHERE c.academy_id = v_academy
      AND c.id = p_course AND c.active AND c.deleted_at IS NULL) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  INSERT INTO public.bookings (academy_id, session_id, player_id, package_id, service_offer_id, community_course_id,
    created_by, notification_owner_id, status, client_can_reject, note, amount_snapshot, currency,
    contract_snapshot, override_reason)
  VALUES (v_academy, p_session, p_player, p_package, (p_ev ->> 'session_offer_id')::uuid, p_course,
    auth.uid(), p_owner, p_status, p_status = 'CONFIRMED', nullif(btrim(p_note), ''),
    (p_ev ->> 'amount')::numeric, p_ev ->> 'currency', p_ev -> 'contract', p_override_reason)
  RETURNING id INTO v_id;
  IF p_status = 'CONFIRMED' THEN
    UPDATE public.sessions SET occupied_places = occupied_places + 1 WHERE academy_id = v_academy AND id = p_session;
  END IF;
  RETURN v_id;
END;
$$;

-- Terminal cancellation/rejection of an active booking. Caller holds all locks
-- and authorized the actor. A CONFIRMED booking releases its logical hold and
-- its place, without any ledger movement (no credit was debited).
CREATE FUNCTION private.terminate_booking(p_ctx jsonb, p_booking uuid, p_status text, p_reason text, p_effect text) RETURNS bigint
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  v_academy uuid := (p_ctx ->> 'academy_id')::uuid;
  b public.bookings;
  v_before text;
BEGIN
  SELECT * INTO b FROM public.bookings WHERE academy_id = v_academy AND id = p_booking;
  IF b.status NOT IN ('PENDING','CONFIRMED') THEN PERFORM private.fail('INVALID_STATE'); END IF;
  v_before := b.status;
  IF b.status = 'CONFIRMED' THEN
    IF private.booking_net_consumed(v_academy, b.package_id, b.id) <> 0 THEN
      PERFORM private.fail('LEGACY_CREDIT_UNRESOLVED');
    END IF;
    UPDATE public.sessions SET occupied_places = occupied_places - 1 WHERE academy_id = v_academy AND id = b.session_id;
  END IF;
  UPDATE public.bookings SET status = p_status, revision = revision + 1
    WHERE academy_id = v_academy AND id = p_booking RETURNING * INTO b;
  PERFORM private.booking_event(p_ctx, p_effect || ':event', b.id, p_status, v_before, p_status, b.revision,
    p_reason, jsonb_build_object('hold_released', v_before = 'CONFIRMED'));
  PERFORM private.enqueue(p_ctx, p_effect || ':notify', 'BOOKING_' || p_status, b.id, NULL,
    jsonb_build_object('booking_id', b.id, 'session_id', b.session_id, 'player_id', b.player_id, 'status', p_status));
  PERFORM private.cancel_reminder(b.id, b.revision, p_status);
  RETURN b.revision;
END;
$$;

CREATE FUNCTION private.booking_result(p_outcome text, p_booking uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT jsonb_build_object('outcome', p_outcome, 'booking_id', b.id, 'status', b.status, 'revision', b.revision)
  FROM public.bookings b WHERE b.id = p_booking;
$$;

CREATE FUNCTION public.request_booking(p_academy uuid, p_session uuid, p_player uuid, p_package uuid,
  p_operation_key uuid, p_note text DEFAULT NULL, p_community_course uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; ev jsonb; v_id uuid; v_bad text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'request_booking', p_operation_key, jsonb_build_object('session', p_session,
    'player', p_player, 'package', p_package, 'note', p_note, 'course', p_community_course));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.request');
  IF NOT (private.linked_player(p_academy, p_player) OR private.local_permission(p_academy, 'bookings.schedule')) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  PERFORM private.lock_booking_graph(p_academy, p_player, p_session, p_package);
  ev := private.evaluate_booking(p_academy, p_session, p_player, p_package, NULL);
  v_bad := private.uncovered(ev -> 'violations', '{}');
  IF v_bad IS NOT NULL THEN PERFORM private.fail(private.violation_code(v_bad)); END IF;
  v_id := private.insert_booking(ctx, p_session, p_player, p_package, 'PENDING', ev, p_note, p_community_course, auth.uid(), NULL);
  PERFORM private.booking_event(ctx, 'event', v_id, 'REQUESTED', NULL, 'PENDING', 1, NULL,
    jsonb_build_object('r', ev -> 'r', 'h', ev -> 'h', 'a', ev -> 'a'));
  PERFORM private.enqueue(ctx, 'notify', 'BOOKING_REQUESTED', v_id, NULL,
    jsonb_build_object('booking_id', v_id, 'session_id', p_session, 'player_id', p_player, 'status', 'PENDING'));
  PERFORM private.audit(ctx, 'audit', 'booking.requested', 'booking', v_id);
  RETURN private.cmd_finish(ctx, private.booking_result('REQUESTED', v_id));
END;
$$;

CREATE FUNCTION public.schedule_booking(p_academy uuid, p_session uuid, p_player uuid, p_package uuid,
  p_operation_key uuid, p_overrides text[] DEFAULT '{}', p_reason text DEFAULT NULL,
  p_note text DEFAULT NULL, p_community_course uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  ctx jsonb; ev jsonb; v_id uuid; v_bad text; v_reason text; v_used jsonb; v_status text;
  v_overrides text[] := coalesce(p_overrides, '{}');
BEGIN
  ctx := private.cmd_begin(p_academy, 'schedule_booking', p_operation_key, jsonb_build_object('session', p_session,
    'player', p_player, 'package', p_package, 'overrides', to_jsonb(v_overrides), 'reason', p_reason,
    'note', p_note, 'course', p_community_course));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.schedule');
  v_reason := private.check_overrides(p_academy, v_overrides, p_reason);
  PERFORM private.lock_booking_graph(p_academy, p_player, p_session, p_package);
  ev := private.evaluate_booking(p_academy, p_session, p_player, p_package, NULL);
  v_bad := private.uncovered(ev -> 'violations', v_overrides);
  IF v_bad IS NOT NULL THEN PERFORM private.fail(private.violation_code(v_bad)); END IF;
  v_used := private.used_overrides(ev -> 'violations', v_overrides);
  -- D34: quota override without free credit records a PENDING request only.
  v_status := CASE WHEN v_used ? 'quota' THEN 'PENDING' ELSE 'CONFIRMED' END;
  v_id := private.insert_booking(ctx, p_session, p_player, p_package, v_status, ev, p_note, p_community_course, NULL,
    CASE WHEN jsonb_array_length(v_used) > 0 THEN v_reason END);
  PERFORM private.booking_event(ctx, 'event', v_id, CASE v_status WHEN 'CONFIRMED' THEN 'SCHEDULED' ELSE 'REQUESTED' END,
    NULL, v_status, 1, NULL, jsonb_build_object('r', ev -> 'r', 'h_before', ev -> 'h',
      'h_after', (ev ->> 'h')::integer + CASE v_status WHEN 'CONFIRMED' THEN 1 ELSE 0 END, 'a_before', ev -> 'a'));
  IF jsonb_array_length(v_used) > 0 THEN
    PERFORM private.booking_event(ctx, 'override', v_id, 'OVERRIDE_USED', NULL, v_status, 1, v_reason,
      jsonb_build_object('overrides', v_used, 'requested', to_jsonb(v_overrides)));
  END IF;
  PERFORM private.enqueue(ctx, 'notify', CASE v_status WHEN 'CONFIRMED' THEN 'BOOKING_SCHEDULED' ELSE 'BOOKING_REQUESTED' END,
    v_id, NULL, jsonb_build_object('booking_id', v_id, 'session_id', p_session, 'player_id', p_player, 'status', v_status));
  IF v_status = 'CONFIRMED' THEN
    PERFORM private.schedule_reminder(p_academy, v_id, 1, (ev ->> 'starts_at')::timestamptz);
  END IF;
  PERFORM private.audit(ctx, 'audit', 'booking.scheduled', 'booking', v_id, v_reason, jsonb_build_object('overrides', v_used));
  RETURN private.cmd_finish(ctx, private.booking_result(CASE v_status WHEN 'CONFIRMED' THEN 'SCHEDULED' ELSE 'PENDING_CREDIT' END, v_id));
END;
$$;

CREATE FUNCTION public.approve_booking(p_academy uuid, p_booking uuid, p_expected_revision bigint,
  p_operation_key uuid, p_overrides text[] DEFAULT '{}', p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  ctx jsonb; ev jsonb; b public.bookings; v_bad text; v_reason text; v_used jsonb;
  v_overrides text[] := coalesce(p_overrides, '{}');
BEGIN
  ctx := private.cmd_begin(p_academy, 'approve_booking', p_operation_key, jsonb_build_object('booking', p_booking,
    'revision', p_expected_revision, 'overrides', to_jsonb(v_overrides), 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.approve');
  v_reason := private.check_overrides(p_academy, v_overrides, p_reason);
  b := private.lock_booking(p_academy, p_booking);
  PERFORM private.check_revision(b.revision, p_expected_revision);
  IF b.status <> 'PENDING' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  ev := private.evaluate_booking(p_academy, b.session_id, b.player_id, b.package_id, b.id);
  -- A quota override can never confirm without free credit (D34).
  v_bad := private.uncovered(ev -> 'violations', array_remove(v_overrides, 'quota'));
  IF v_bad IS NOT NULL THEN PERFORM private.fail(private.violation_code(v_bad)); END IF;
  v_used := private.used_overrides(ev -> 'violations', v_overrides);
  UPDATE public.bookings SET status = 'CONFIRMED', revision = revision + 1, client_can_reject = false,
    override_reason = CASE WHEN jsonb_array_length(v_used) > 0 THEN v_reason ELSE override_reason END
  WHERE academy_id = p_academy AND id = p_booking RETURNING * INTO b;
  UPDATE public.sessions SET occupied_places = occupied_places + 1 WHERE academy_id = p_academy AND id = b.session_id;
  PERFORM private.booking_event(ctx, 'event', b.id, 'APPROVED', 'PENDING', 'CONFIRMED', b.revision, NULL,
    jsonb_build_object('r', ev -> 'r', 'h_before', ev -> 'h', 'h_after', (ev ->> 'h')::integer + 1, 'a_before', ev -> 'a'));
  IF jsonb_array_length(v_used) > 0 THEN
    PERFORM private.booking_event(ctx, 'override', b.id, 'OVERRIDE_USED', 'PENDING', 'CONFIRMED', b.revision, v_reason,
      jsonb_build_object('overrides', v_used, 'requested', to_jsonb(v_overrides)));
  END IF;
  PERFORM private.enqueue(ctx, 'notify', 'BOOKING_APPROVED', b.id, NULL,
    jsonb_build_object('booking_id', b.id, 'session_id', b.session_id, 'player_id', b.player_id, 'status', 'CONFIRMED'));
  PERFORM private.schedule_reminder(p_academy, b.id, b.revision, (ev ->> 'starts_at')::timestamptz);
  PERFORM private.audit(ctx, 'audit', 'booking.approved', 'booking', b.id, v_reason, jsonb_build_object('overrides', v_used));
  RETURN private.cmd_finish(ctx, private.booking_result('APPROVED', b.id));
END;
$$;

CREATE FUNCTION public.reject_booking(p_academy uuid, p_booking uuid, p_expected_revision bigint,
  p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; b public.bookings; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'reject_booking', p_operation_key, jsonb_build_object('booking', p_booking,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.reject');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO b FROM public.bookings WHERE academy_id = p_academy AND id = p_booking;
  IF NOT FOUND OR NOT (private.local_permission(p_academy, 'bookings.schedule')
      OR private.linked_player(p_academy, b.player_id)) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  b := private.lock_booking(p_academy, p_booking);
  PERFORM private.check_revision(b.revision, p_expected_revision);
  IF NOT private.local_permission(p_academy, 'bookings.schedule') THEN
    -- Member refusal of a staff-scheduled booking awaits D05.
    IF b.status = 'CONFIRMED' AND b.client_can_reject THEN PERFORM private.fail('MEMBER_POLICY_UNRESOLVED'); END IF;
    IF b.status = 'CONFIRMED' THEN PERFORM private.fail('MEMBER_REJECTION_DISABLED'); END IF;
    PERFORM private.fail('INVALID_STATE');
  END IF;
  IF b.status <> 'PENDING' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  PERFORM private.terminate_booking(ctx, b.id, 'REJECTED', v_reason, 'reject');
  PERFORM private.audit(ctx, 'audit', 'booking.rejected', 'booking', b.id, v_reason);
  RETURN private.cmd_finish(ctx, private.booking_result('REJECTED', b.id));
END;
$$;

CREATE FUNCTION public.cancel_booking(p_academy uuid, p_booking uuid, p_expected_revision bigint,
  p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; b public.bookings; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'cancel_booking', p_operation_key, jsonb_build_object('booking', p_booking,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.cancel');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO b FROM public.bookings WHERE academy_id = p_academy AND id = p_booking;
  IF NOT FOUND OR NOT (private.local_permission(p_academy, 'bookings.schedule')
      OR private.linked_player(p_academy, b.player_id)) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  b := private.lock_booking(p_academy, p_booking);
  PERFORM private.check_revision(b.revision, p_expected_revision);
  -- Members withdraw their own PENDING request; CONFIRMED awaits D05.
  IF b.status = 'CONFIRMED' AND NOT private.local_permission(p_academy, 'bookings.schedule') THEN
    PERFORM private.fail('MEMBER_POLICY_UNRESOLVED');
  END IF;
  PERFORM private.terminate_booking(ctx, b.id, 'CANCELLED', v_reason, 'cancel');
  PERFORM private.audit(ctx, 'audit', 'booking.cancelled', 'booking', b.id, v_reason);
  RETURN private.cmd_finish(ctx, private.booking_result('CANCELLED', b.id));
END;
$$;

-- Attendance (D04): PRESENT consumes the booking's own reserved credit even when
-- A = 0; ABSENT releases the hold without debit. Corrections compensate the exact
-- debit once, or debit again only with free credit (A >= 1).
CREATE FUNCTION public.record_attendance(p_academy uuid, p_booking uuid, p_attended boolean,
  p_expected_revision bigint, p_operation_key uuid, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  ctx jsonb; b public.bookings; att public.booking_attendance; v_reason text;
  v_starts timestamptz; v_net integer; v_r integer; v_h integer; v_debit uuid; v_event text; v_before text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'record_attendance', p_operation_key, jsonb_build_object('booking', p_booking,
    'attended', p_attended, 'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  IF p_attended IS NULL THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  SELECT * INTO b FROM public.bookings WHERE academy_id = p_academy AND id = p_booking;
  -- Coaches act on their assignments only; others need the operational scope.
  IF NOT FOUND OR NOT (private.local_permission(p_academy, 'bookings.schedule')
      OR private.assigned_session(p_academy, b.session_id)) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  b := private.lock_booking(p_academy, p_booking);
  SELECT starts_at INTO v_starts FROM public.sessions WHERE academy_id = p_academy AND id = b.session_id;
  IF v_starts > transaction_timestamp() THEN PERFORM private.fail('TOO_EARLY'); END IF;
  SELECT * INTO att FROM public.booking_attendance WHERE booking_id = b.id FOR UPDATE;
  IF b.status = 'COMPLETED' AND att.attended IS NOT DISTINCT FROM p_attended THEN
    PERFORM private.require_permission(p_academy, 'attendance.record');
    RETURN private.cmd_finish(ctx, private.booking_result('NO_CHANGE', b.id));
  END IF;
  PERFORM private.check_revision(b.revision, p_expected_revision);
  IF b.status NOT IN ('CONFIRMED','COMPLETED') THEN PERFORM private.fail('INVALID_STATE'); END IF;
  v_net := private.booking_net_consumed(p_academy, b.package_id, b.id);
  SELECT remaining_sessions INTO v_r FROM public.player_packages WHERE academy_id = p_academy AND id = b.package_id;
  IF b.status = 'CONFIRMED' OR att.booking_id IS NULL THEN
    -- First observation: from CONFIRMED, or after an administrative completion.
    PERFORM private.require_permission(p_academy, 'attendance.record');
    v_reason := private.reason(p_reason, false);
    IF b.status = 'CONFIRMED' THEN
      IF v_net <> 0 THEN PERFORM private.fail('LEGACY_CREDIT_UNRESOLVED'); END IF;
      IF p_attended THEN
        PERFORM private.ledger_move(ctx, 'consume', b.package_id, b.id, -1, 'SESSION_CONSUMED');
      END IF;
    ELSIF v_net <> 1 THEN
      PERFORM private.fail('LEGACY_CREDIT_UNRESOLVED');
    ELSIF NOT p_attended THEN
      v_debit := (SELECT l.id FROM private.course_ledger l WHERE l.academy_id = p_academy AND l.package_id = b.package_id
        AND l.booking_id = b.id AND l.reason = 'SESSION_CONSUMED'
        AND NOT EXISTS (SELECT 1 FROM private.course_ledger r WHERE r.reverses_entry_id = l.id)
        ORDER BY l.created_at DESC, l.id DESC LIMIT 1);
      PERFORM private.ledger_move(ctx, 'compensate', b.package_id, b.id, 1, 'ATTENDANCE_CORRECTION', NULL, v_debit);
    END IF;
    INSERT INTO public.booking_attendance (booking_id, academy_id, attended, recorded_by, recorded_at)
    VALUES (b.id, p_academy, p_attended, auth.uid(), transaction_timestamp());
    v_event := 'ATTENDANCE_RECORDED';
  ELSE
    PERFORM private.require_permission(p_academy, 'attendance.correct');
    v_reason := private.reason(p_reason, true);
    IF p_attended THEN
      -- ABSENT -> PRESENT: needs free credit; never takes another booking's hold.
      v_h := private.package_hold(p_academy, b.package_id);
      IF v_net <> 0 THEN PERFORM private.fail('LEGACY_CREDIT_UNRESOLVED'); END IF;
      IF v_r - v_h < 1 THEN PERFORM private.fail('CREDIT_UNAVAILABLE'); END IF;
      PERFORM private.ledger_move(ctx, 'consume', b.package_id, b.id, -1, 'SESSION_CONSUMED');
    ELSE
      IF v_net <> 1 THEN PERFORM private.fail('LEGACY_CREDIT_UNRESOLVED'); END IF;
      v_debit := (SELECT l.id FROM private.course_ledger l WHERE l.academy_id = p_academy AND l.package_id = b.package_id
        AND l.booking_id = b.id AND l.reason = 'SESSION_CONSUMED'
        AND NOT EXISTS (SELECT 1 FROM private.course_ledger r WHERE r.reverses_entry_id = l.id)
        ORDER BY l.created_at DESC, l.id DESC LIMIT 1);
      PERFORM private.ledger_move(ctx, 'compensate', b.package_id, b.id, 1, 'ATTENDANCE_CORRECTION', NULL, v_debit);
    END IF;
    UPDATE public.booking_attendance SET attended = p_attended, recorded_by = auth.uid(),
      recorded_at = transaction_timestamp(), revision = revision + 1 WHERE booking_id = b.id;
    v_event := 'ATTENDANCE_CORRECTED';
  END IF;
  v_before := b.status;
  UPDATE public.bookings SET status = 'COMPLETED', completion_source = coalesce(completion_source, 'ATTENDANCE'),
    revision = revision + 1 WHERE academy_id = p_academy AND id = b.id RETURNING * INTO b;
  PERFORM private.booking_event(ctx, 'event', b.id, v_event, v_before, 'COMPLETED', b.revision, v_reason, jsonb_build_object('attended', p_attended, 'r_before', v_r,
      'r_after', (SELECT remaining_sessions FROM public.player_packages WHERE academy_id = p_academy AND id = b.package_id)));
  PERFORM private.cancel_reminder(b.id, b.revision, 'COMPLETED');
  PERFORM private.audit(ctx, 'audit', lower(v_event), 'booking', b.id, v_reason, jsonb_build_object('attended', p_attended));
  RETURN private.cmd_finish(ctx, private.booking_result(v_event, b.id));
END;
$$;

CREATE FUNCTION public.complete_booking(p_academy uuid, p_booking uuid, p_expected_revision bigint,
  p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; b public.bookings; v_reason text; v_starts timestamptz;
BEGIN
  ctx := private.cmd_begin(p_academy, 'complete_booking', p_operation_key, jsonb_build_object('booking', p_booking,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.complete');
  v_reason := private.reason(p_reason, true);
  b := private.lock_booking(p_academy, p_booking);
  PERFORM private.check_revision(b.revision, p_expected_revision);
  IF b.status <> 'CONFIRMED' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  SELECT starts_at INTO v_starts FROM public.sessions WHERE academy_id = p_academy AND id = b.session_id;
  IF v_starts > transaction_timestamp() THEN PERFORM private.fail('COMPLETION_BEFORE_START_UNRESOLVED'); END IF;
  IF private.booking_net_consumed(p_academy, b.package_id, b.id) <> 0 THEN
    PERFORM private.fail('LEGACY_CREDIT_UNRESOLVED');
  END IF;
  -- Transfers the reserved credit to consumption; no attendance is fabricated.
  PERFORM private.ledger_move(ctx, 'consume', b.package_id, b.id, -1, 'SESSION_CONSUMED');
  UPDATE public.bookings SET status = 'COMPLETED', completion_source = 'ADMIN', revision = revision + 1
    WHERE academy_id = p_academy AND id = b.id RETURNING * INTO b;
  PERFORM private.booking_event(ctx, 'event', b.id, 'COMPLETED', 'CONFIRMED', 'COMPLETED', b.revision, v_reason);
  PERFORM private.cancel_reminder(b.id, b.revision, 'COMPLETED');
  PERFORM private.audit(ctx, 'audit', 'booking.completed', 'booking', b.id, v_reason);
  RETURN private.cmd_finish(ctx, private.booking_result('COMPLETED', b.id));
END;
$$;

-- Archive (D31): COMPLETED keeps places, ledger and credits. An active booking
-- is first cancelled in the same transaction instead of escaping uniqueness.
CREATE FUNCTION public.archive_booking(p_academy uuid, p_booking uuid, p_expected_revision bigint,
  p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; b public.bookings; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_booking', p_operation_key, jsonb_build_object('booking', p_booking,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'bookings.archive');
  v_reason := private.reason(p_reason, true);
  b := private.lock_booking(p_academy, p_booking);
  PERFORM private.check_revision(b.revision, p_expected_revision);
  IF b.deleted_at IS NOT NULL THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF b.status IN ('PENDING','CONFIRMED') THEN
    PERFORM private.require_permission(p_academy, 'bookings.cancel');
    PERFORM private.terminate_booking(ctx, b.id, 'CANCELLED', v_reason, 'cancel');
  END IF;
  UPDATE public.bookings SET deleted_at = transaction_timestamp(), deleted_by = auth.uid(), revision = revision + 1
    WHERE academy_id = p_academy AND id = b.id RETURNING * INTO b;
  PERFORM private.booking_event(ctx, 'event', b.id, 'ARCHIVED', b.status, b.status, b.revision, v_reason);
  PERFORM private.audit(ctx, 'audit', 'booking.archived', 'booking', b.id, v_reason);
  RETURN private.cmd_finish(ctx, private.booking_result('ARCHIVED', b.id));
END;
$$;

-- Client entry points: authenticated only; the private helpers stay unreachable.
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('request_booking','schedule_booking','approve_booking',
      'reject_booking','cancel_booking','record_attendance','complete_booking','archive_booking') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END;
$$;

-- Schema-level default privileges cannot remove PUBLIC's global EXECUTE default,
-- so every internal helper created above is revoked explicitly.
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proacl IS NULL LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f);
  END LOOP;
END;
$$;
