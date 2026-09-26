-- Phase 3C. Shared building blocks of client commands. Every mutation is one
-- SECURITY DEFINER RPC in one transaction: an error rolls back state, counters,
-- ledger, audit, outbox and receipt together. Nothing here is client-callable.
--
-- Error contract: MESSAGE is a stable code (CREDIT_UNAVAILABLE, ...). SQLSTATE is
-- 42501 for FORBIDDEN, P0002 for NOT_FOUND (also used for resources outside the
-- actor's scope, so existence never leaks), 22023 for invalid input and P0001
-- for business refusals.

CREATE FUNCTION private.fail(p_code text, p_state text DEFAULT 'P0001') RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = p_state, MESSAGE = p_code;
END;
$$;

CREATE FUNCTION private.require_permission(p_academy uuid, p_permission text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NOT private.local_permission(p_academy, p_permission) THEN
    PERFORM private.fail('FORBIDDEN', '42501');
  END IF;
END;
$$;

CREATE FUNCTION private.require_platform_permission(p_permission text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NOT private.platform_permission(p_permission) THEN
    PERFORM private.fail('FORBIDDEN', '42501');
  END IF;
END;
$$;

-- Trimmed reason; required reasons cannot be blank. Bounded like the DDL.
CREATE FUNCTION private.reason(p_reason text, p_required boolean) RETURNS text
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE v text := nullif(btrim(p_reason), '');
BEGIN
  IF v IS NULL AND p_required THEN PERFORM private.fail('REASON_REQUIRED', '22023'); END IF;
  IF length(v) > 1000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  RETURN v;
END;
$$;

CREATE FUNCTION private.require_text(p_value text, p_max integer) RETURNS text
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF p_value IS NULL OR length(btrim(p_value)) = 0 OR length(btrim(p_value)) > p_max THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  RETURN btrim(p_value);
END;
$$;

-- Exact decimal string validated before any numeric(18,2) cast: XAF integer
-- (1000 or 1000.00), other currencies at most two decimals. No float, no rounding.
CREATE FUNCTION private.money(p_amount text, p_currency text, p_allow_zero boolean) RETURNS numeric
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  v numeric;
  v_pattern text := CASE WHEN p_currency = 'XAF' THEN '^[0-9]{1,16}([.]0{1,2})?$' ELSE '^[0-9]{1,16}([.][0-9]{1,2})?$' END;
BEGIN
  IF p_currency IS NULL OR p_currency NOT IN ('AED','XAF','EUR','USD','MAD') THEN
    PERFORM private.fail('INVALID_CURRENCY', '22023');
  END IF;
  IF p_amount IS NULL OR p_amount !~ v_pattern THEN
    PERFORM private.fail('INVALID_AMOUNT', '22023');
  END IF;
  v := p_amount::numeric;
  IF v = 0 AND NOT p_allow_zero THEN PERFORM private.fail('INVALID_AMOUNT', '22023'); END IF;
  RETURN v;
END;
$$;

-- Idempotent command start. The receipt key is (actor, rpc, operation_key); the
-- hash covers rpc, tenant and arguments. Concurrent calls with one key serialize
-- on a transaction advisory lock; the loser then sees the committed receipt.
-- p_platform: the caller checks a platform permission instead of tenant access.
CREATE FUNCTION private.cmd_begin(p_academy uuid, p_rpc text, p_key uuid, p_args jsonb, p_platform boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_hash text;
  v_prior private.command_receipts%ROWTYPE;
BEGIN
  PERFORM private.require_active_actor();
  IF p_key IS NULL THEN PERFORM private.fail('OPERATION_KEY_REQUIRED', '22023'); END IF;
  IF NOT p_platform AND (p_academy IS NULL OR NOT private.local_permission(p_academy, 'academy.read')) THEN
    PERFORM private.fail('FORBIDDEN', '42501');
  END IF;
  v_hash := encode(sha256(convert_to(jsonb_build_array(p_rpc, p_academy, p_args)::text, 'UTF8')), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::text || '/' || p_rpc || '/' || p_key::text, 0));
  SELECT * INTO v_prior FROM private.command_receipts
    WHERE actor_ref = v_actor::text AND rpc_name = p_rpc AND operation_key = p_key;
  IF FOUND THEN
    IF v_prior.request_hash <> v_hash THEN PERFORM private.fail('IDEMPOTENCY_CONFLICT', '22023'); END IF;
    RETURN jsonb_build_object('replay', v_prior.result);
  END IF;
  RETURN jsonb_build_object('operation_id', gen_random_uuid(), 'academy_id', p_academy,
    'rpc', p_rpc, 'key', p_key, 'hash', v_hash);
END;
$$;

-- Receipt written last; deferred FKs let effects reference it. The receipt
-- scope equals the tenant of every effect (checked by receipt_scope triggers).
CREATE FUNCTION private.cmd_finish(p_ctx jsonb, p_result jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  v_result jsonb := jsonb_build_object('operation_id', p_ctx ->> 'operation_id') || p_result;
  v_academy uuid := (p_ctx ->> 'academy_id')::uuid;
BEGIN
  INSERT INTO private.command_receipts (id, scope, academy_id, actor_kind, actor_user_id, actor_ref,
    rpc_name, operation_key, request_hash, result, completed_at)
  VALUES ((p_ctx ->> 'operation_id')::uuid, CASE WHEN v_academy IS NULL THEN 'PLATFORM' ELSE 'TENANT' END,
    v_academy, 'USER', auth.uid(), auth.uid()::text, p_ctx ->> 'rpc', (p_ctx ->> 'key')::uuid,
    p_ctx ->> 'hash', v_result, clock_timestamp());
  RETURN v_result;
END;
$$;

CREATE FUNCTION private.audit(p_ctx jsonb, p_effect text, p_action text, p_type text, p_id uuid,
  p_reason text DEFAULT NULL, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  INSERT INTO private.audit_log (scope, academy_id, operation_id, effect_key, actor_kind, actor_user_id,
    actor_ref, action, resource_type, resource_id, occurred_at, reason, metadata)
  VALUES (CASE WHEN p_ctx ->> 'academy_id' IS NULL THEN 'PLATFORM' ELSE 'TENANT' END,
    (p_ctx ->> 'academy_id')::uuid, (p_ctx ->> 'operation_id')::uuid, p_effect, 'USER', auth.uid(),
    auth.uid()::text, p_action, p_type, p_id, transaction_timestamp(), p_reason, p_metadata);
$$;

CREATE FUNCTION private.booking_event(p_ctx jsonb, p_effect text, p_booking uuid, p_type text,
  p_before text, p_after text, p_revision bigint, p_reason text DEFAULT NULL, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  INSERT INTO private.booking_events (academy_id, operation_id, effect_key, actor_kind, actor_user_id,
    actor_ref, booking_id, event_type, before_status, after_status, occurred_at, reason, metadata, booking_revision)
  VALUES ((p_ctx ->> 'academy_id')::uuid, (p_ctx ->> 'operation_id')::uuid, p_effect, 'USER', auth.uid(),
    auth.uid()::text, p_booking, p_type, p_before, p_after, transaction_timestamp(), p_reason, p_metadata, p_revision);
$$;

-- Durable outbox: the worker (3D) expands recipients after commit. The snapshot
-- holds identifiers only; no email, name or link is copied here.
CREATE FUNCTION private.enqueue(p_ctx jsonb, p_effect text, p_type text, p_booking uuid DEFAULT NULL,
  p_invitation uuid DEFAULT NULL, p_snapshot jsonb DEFAULT '{}'::jsonb) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  INSERT INTO private.notification_events (scope, academy_id, operation_id, effect_key, booking_id,
    invitation_id, event_type, snapshot, status, next_attempt_at)
  VALUES ('TENANT', (p_ctx ->> 'academy_id')::uuid, (p_ctx ->> 'operation_id')::uuid, p_effect, p_booking,
    p_invitation, p_type, p_snapshot, 'QUEUED', transaction_timestamp());
$$;

-- One current reminder per booking, 24h before start (V1 source rule); the
-- worker revalidates booking revision/state/date before sending.
CREATE FUNCTION private.schedule_reminder(p_academy uuid, p_booking uuid, p_revision bigint, p_starts_at timestamptz) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  INSERT INTO private.booking_reminders (booking_id, academy_id, booking_revision, status, due_at, starts_at, reason_code)
  VALUES (p_booking, p_academy, p_revision,
    CASE WHEN p_starts_at - interval '24 hours' > transaction_timestamp() THEN 'SCHEDULED' ELSE 'SKIPPED' END,
    CASE WHEN p_starts_at - interval '24 hours' > transaction_timestamp() THEN p_starts_at - interval '24 hours' END,
    p_starts_at,
    CASE WHEN p_starts_at - interval '24 hours' > transaction_timestamp() THEN NULL ELSE 'DUE_IN_PAST' END)
  ON CONFLICT (booking_id) DO UPDATE SET booking_revision = EXCLUDED.booking_revision,
    status = EXCLUDED.status, due_at = EXCLUDED.due_at, starts_at = EXCLUDED.starts_at,
    reason_code = EXCLUDED.reason_code, event_id = NULL;
$$;

CREATE FUNCTION private.cancel_reminder(p_booking uuid, p_revision bigint, p_reason text) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  UPDATE private.booking_reminders SET status = 'CANCELLED', booking_revision = p_revision,
    reason_code = p_reason, due_at = NULL
  WHERE booking_id = p_booking AND status IN ('SCHEDULED','QUEUED');
$$;

-- Credit arithmetic (D30). Net consumed per booking/package is 0 or 1; H counts
-- CONFIRMED bookings whose net is 0, whatever deleted_at or the caller's scope.
-- Callers hold the package row lock before reading these values.
CREATE FUNCTION private.booking_net_consumed(p_academy uuid, p_package uuid, p_booking uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT coalesce(-sum(l.delta), 0)::integer FROM private.course_ledger l
  WHERE l.academy_id = p_academy AND l.package_id = p_package AND l.booking_id = p_booking
    AND l.reason IN ('SESSION_CONSUMED','ATTENDANCE_CORRECTION','BOOKING_CANCELLATION_CORRECTION');
$$;

CREATE FUNCTION private.package_hold(p_academy uuid, p_package uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT count(*)::integer FROM public.bookings b
  WHERE b.academy_id = p_academy AND b.package_id = p_package AND b.status = 'CONFIRMED'
    AND private.booking_net_consumed(p_academy, p_package, b.id) = 0;
$$;

-- Ledger movement and balance cache in the same transaction. R never < 0 (CHECK);
-- status follows the balance except for PENDING/ARCHIVED packages.
CREATE FUNCTION private.ledger_move(p_ctx jsonb, p_effect text, p_package uuid, p_booking uuid, p_delta integer,
  p_reason text, p_reason_text text DEFAULT NULL, p_reverses uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  v_academy uuid := (p_ctx ->> 'academy_id')::uuid;
  v_id uuid;
BEGIN
  INSERT INTO private.course_ledger (academy_id, operation_id, effect_key, actor_kind, actor_user_id, actor_ref,
    package_id, booking_id, delta, reason, occurred_at, reason_text, reverses_entry_id)
  VALUES (v_academy, (p_ctx ->> 'operation_id')::uuid, p_effect, 'USER', auth.uid(), auth.uid()::text,
    p_package, p_booking, p_delta, p_reason, transaction_timestamp(), p_reason_text, p_reverses)
  RETURNING id INTO v_id;
  UPDATE public.player_packages SET remaining_sessions = remaining_sessions + p_delta, updated_by = auth.uid(),
    status = CASE WHEN status IN ('PENDING','ARCHIVED') THEN status
      WHEN remaining_sessions + p_delta = 0 THEN 'EXHAUSTED' ELSE 'ACTIVE' END
  WHERE academy_id = v_academy AND id = p_package;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION private.fail(text,text), private.require_permission(uuid,text),
  private.require_platform_permission(text), private.reason(text,boolean), private.require_text(text,integer),
  private.money(text,text,boolean), private.cmd_begin(uuid,text,uuid,jsonb,boolean), private.cmd_finish(jsonb,jsonb),
  private.audit(jsonb,text,text,text,uuid,text,jsonb),
  private.booking_event(jsonb,text,uuid,text,text,text,bigint,text,jsonb),
  private.enqueue(jsonb,text,text,uuid,uuid,jsonb), private.schedule_reminder(uuid,uuid,bigint,timestamptz),
  private.cancel_reminder(uuid,bigint,text), private.booking_net_consumed(uuid,uuid,uuid),
  private.package_hold(uuid,uuid), private.ledger_move(jsonb,text,uuid,uuid,integer,text,text,uuid)
  FROM PUBLIC, anon, authenticated;
