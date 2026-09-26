-- Phase 3C: players, family links, packages, credit ledger, payments, invoices.
-- Lock order: player -> package -> payment. Money is validated as an exact
-- decimal string before any cast (§5). No online payment, no invented pricing.

CREATE FUNCTION private.lock_player(p_academy uuid, p_player uuid) RETURNS public.players
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE p public.players;
BEGIN
  SELECT * INTO p FROM public.players WHERE academy_id = p_academy AND id = p_player FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  RETURN p;
END;
$$;

CREATE FUNCTION private.lock_package(p_academy uuid, p_package uuid) RETURNS public.player_packages
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE k public.player_packages;
BEGIN
  SELECT * INTO k FROM public.player_packages WHERE academy_id = p_academy AND id = p_package;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.lock_player(p_academy, k.player_id);
  SELECT * INTO k FROM public.player_packages WHERE academy_id = p_academy AND id = p_package FOR UPDATE;
  RETURN k;
END;
$$;

CREATE FUNCTION private.validate_identity(p_birth_date date, p_reported_age integer, p_gender text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF p_birth_date IS NOT NULL AND (p_birth_date > current_date OR p_birth_date < date '1900-01-01')
     OR p_reported_age IS NOT NULL AND p_reported_age NOT BETWEEN 3 AND 80
     OR p_gender IS NOT NULL AND p_gender NOT IN ('FEMALE','MALE','OTHER') THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
END;
$$;

-- Owner/Admin/Manager create any player; a PARENT creates a child linked as
-- GUARDIAN, a STUDENT creates the SELF record. No other family access is created.
CREATE FUNCTION public.create_player(p_academy uuid, p_first_name text, p_last_name text, p_operation_key uuid,
  p_birth_date date DEFAULT NULL, p_reported_age integer DEFAULT NULL, p_gender text DEFAULT NULL,
  p_community uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid; v_link text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_player', p_operation_key, jsonb_build_object('first_name', p_first_name,
    'last_name', p_last_name, 'birth_date', p_birth_date, 'reported_age', p_reported_age, 'gender', p_gender,
    'community', p_community));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'players.create');
  PERFORM private.validate_identity(p_birth_date, p_reported_age, p_gender);
  IF NOT private.local_permission(p_academy, 'players.archive') THEN
    v_link := CASE WHEN private.has_local_role(p_academy, 'PARENT') THEN 'GUARDIAN'
      WHEN private.has_local_role(p_academy, 'STUDENT') THEN 'SELF' END;
    IF v_link IS NULL OR p_community IS NOT NULL THEN PERFORM private.fail('FORBIDDEN', '42501'); END IF;
    IF v_link = 'SELF' AND EXISTS (SELECT 1 FROM public.player_links l WHERE l.academy_id = p_academy
        AND l.user_id = auth.uid() AND l.relationship = 'SELF' AND l.revoked_at IS NULL) THEN
      PERFORM private.fail('SELF_ALREADY_LINKED');
    END IF;
  END IF;
  IF p_community IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.communities c WHERE c.academy_id = p_academy
      AND c.id = p_community AND c.active AND c.deleted_at IS NULL) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  INSERT INTO public.players (academy_id, created_by, updated_by, first_name, last_name, reported_age,
    age_recorded_at, birth_date, gender, status, community_id)
  VALUES (p_academy, auth.uid(), auth.uid(), private.require_text(p_first_name, 80), private.require_text(p_last_name, 80),
    p_reported_age, CASE WHEN p_reported_age IS NOT NULL THEN transaction_timestamp() END, p_birth_date, p_gender,
    'ACTIVE', p_community)
  RETURNING id INTO v_id;
  IF v_link IS NOT NULL THEN
    INSERT INTO public.player_links (academy_id, player_id, user_id, relationship, assigned_by)
    VALUES (p_academy, v_id, auth.uid(), v_link, auth.uid());
  END IF;
  PERFORM private.audit(ctx, 'audit', 'player.created', 'player', v_id, NULL, jsonb_build_object('self_link', v_link));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'player_id', v_id));
END;
$$;

-- NULL keeps a field unchanged. Linked family members edit identity only.
CREATE FUNCTION public.update_player_identity(p_academy uuid, p_player uuid, p_operation_key uuid,
  p_first_name text DEFAULT NULL, p_last_name text DEFAULT NULL, p_birth_date date DEFAULT NULL,
  p_reported_age integer DEFAULT NULL, p_gender text DEFAULT NULL, p_community uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; p public.players; v_fields jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_player_identity', p_operation_key, jsonb_build_object('player', p_player,
    'first_name', p_first_name, 'last_name', p_last_name, 'birth_date', p_birth_date,
    'reported_age', p_reported_age, 'gender', p_gender, 'community', p_community));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'players.update_identity');
  IF NOT private.local_permission(p_academy, 'players.archive') THEN
    IF NOT private.linked_player(p_academy, p_player) THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
    IF p_community IS NOT NULL THEN PERFORM private.fail('FORBIDDEN', '42501'); END IF;
  END IF;
  PERFORM private.validate_identity(p_birth_date, p_reported_age, p_gender);
  p := private.lock_player(p_academy, p_player);
  IF p.deleted_at IS NOT NULL THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF p_community IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.communities c WHERE c.academy_id = p_academy
      AND c.id = p_community AND c.active AND c.deleted_at IS NULL) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  UPDATE public.players SET updated_by = auth.uid(),
    first_name = coalesce(private.require_text(coalesce(p_first_name, first_name), 80), first_name),
    last_name = coalesce(private.require_text(coalesce(p_last_name, last_name), 80), last_name),
    birth_date = coalesce(p_birth_date, birth_date), gender = coalesce(p_gender, gender),
    reported_age = coalesce(p_reported_age, reported_age),
    age_recorded_at = CASE WHEN p_reported_age IS NOT NULL THEN transaction_timestamp() ELSE age_recorded_at END,
    community_id = coalesce(p_community, community_id)
  WHERE academy_id = p_academy AND id = p_player;
  -- Audit names the changed fields, never their personal values.
  v_fields := (SELECT coalesce(jsonb_agg(k), '[]'::jsonb) FROM jsonb_each(jsonb_strip_nulls(jsonb_build_object(
    'first_name', p_first_name, 'last_name', p_last_name, 'birth_date', p_birth_date, 'reported_age', p_reported_age,
    'gender', p_gender, 'community_id', p_community))) AS e(k, v));
  PERFORM private.audit(ctx, 'audit', 'player.identity_updated', 'player', p_player, NULL, jsonb_build_object('fields', v_fields));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'player_id', p_player));
END;
$$;

CREATE FUNCTION public.archive_player(p_academy uuid, p_player uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; p public.players; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_player', p_operation_key, jsonb_build_object('player', p_player, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'players.archive');
  v_reason := private.reason(p_reason, true);
  p := private.lock_player(p_academy, p_player);
  IF p.deleted_at IS NOT NULL THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF EXISTS (SELECT 1 FROM public.bookings b WHERE b.academy_id = p_academy AND b.player_id = p_player
      AND b.status IN ('PENDING','CONFIRMED')) THEN
    PERFORM private.fail('PLAYER_IN_USE');
  END IF;
  UPDATE public.players SET status = 'INACTIVE', deleted_at = transaction_timestamp(), deleted_by = auth.uid(),
    updated_by = auth.uid() WHERE academy_id = p_academy AND id = p_player;
  PERFORM private.audit(ctx, 'audit', 'player.archived', 'player', p_player, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'player_id', p_player));
END;
$$;

CREATE FUNCTION public.assign_player_link(p_academy uuid, p_player uuid, p_user uuid, p_relationship text,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; p public.players; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'assign_player_link', p_operation_key, jsonb_build_object('player', p_player,
    'user', p_user, 'relationship', p_relationship));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'player_links.assign');
  IF p_relationship IS NULL OR p_relationship NOT IN ('SELF','GUARDIAN') THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  p := private.lock_player(p_academy, p_player);
  IF p.deleted_at IS NOT NULL THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.academy_memberships m JOIN public.user_profiles u ON u.id = m.user_id
      WHERE m.academy_id = p_academy AND m.user_id = p_user AND m.status = 'ACTIVE' AND u.status = 'ACTIVE') THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  IF EXISTS (SELECT 1 FROM public.player_links l WHERE l.player_id = p_player AND l.user_id = p_user AND l.revoked_at IS NULL) THEN
    PERFORM private.fail('ACTIVE_LINK_EXISTS');
  END IF;
  IF p_relationship = 'SELF' AND EXISTS (SELECT 1 FROM public.player_links l WHERE l.player_id = p_player
      AND l.relationship = 'SELF' AND l.revoked_at IS NULL) THEN
    PERFORM private.fail('SELF_ALREADY_LINKED');
  END IF;
  INSERT INTO public.player_links (academy_id, player_id, user_id, relationship, assigned_by)
  VALUES (p_academy, p_player, p_user, p_relationship, auth.uid()) RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'player_link.assigned', 'player_link', v_id, NULL,
    jsonb_build_object('player_id', p_player, 'relationship', p_relationship));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ASSIGNED', 'link_id', v_id));
END;
$$;

-- Revocation never designates a successor contact.
CREATE FUNCTION public.revoke_player_link(p_academy uuid, p_link uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; l public.player_links; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'revoke_player_link', p_operation_key, jsonb_build_object('link', p_link, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'player_links.revoke');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO l FROM public.player_links WHERE academy_id = p_academy AND id = p_link;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.lock_player(p_academy, l.player_id);
  SELECT * INTO l FROM public.player_links WHERE id = p_link FOR UPDATE;
  IF l.revoked_at IS NOT NULL THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE public.player_links SET revoked_at = transaction_timestamp(), revoked_by = auth.uid() WHERE id = p_link;
  PERFORM private.audit(ctx, 'audit', 'player_link.revoked', 'player_link', p_link, v_reason,
    jsonb_build_object('player_id', l.player_id, 'was_primary', l.is_primary, 'was_financial_contact', l.is_financial_contact));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'REVOKED', 'link_id', p_link));
END;
$$;

-- Sets exactly the designated primary and financial contacts (NULL clears).
-- Flags are cleared before being set so partial unique indexes never collide.
CREATE FUNCTION public.set_player_contacts(p_academy uuid, p_player uuid, p_primary_link uuid, p_financial_link uuid,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_before jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'set_player_contacts', p_operation_key, jsonb_build_object('player', p_player,
    'primary', p_primary_link, 'financial', p_financial_link));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'player_links.set_contacts');
  PERFORM private.lock_player(p_academy, p_player);
  PERFORM 1 FROM public.player_links WHERE academy_id = p_academy AND player_id = p_player AND revoked_at IS NULL
    ORDER BY id FOR UPDATE;
  IF (p_primary_link IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.player_links l WHERE l.id = p_primary_link
        AND l.academy_id = p_academy AND l.player_id = p_player AND l.revoked_at IS NULL))
     OR (p_financial_link IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.player_links l WHERE l.id = p_financial_link
        AND l.academy_id = p_academy AND l.player_id = p_player AND l.revoked_at IS NULL)) THEN
    PERFORM private.fail('INVALID_LINK');
  END IF;
  v_before := jsonb_build_object(
    'primary', (SELECT id FROM public.player_links WHERE player_id = p_player AND revoked_at IS NULL AND is_primary),
    'financial', (SELECT id FROM public.player_links WHERE player_id = p_player AND revoked_at IS NULL AND is_financial_contact));
  UPDATE public.player_links SET is_primary = false, is_financial_contact = false
    WHERE player_id = p_player AND revoked_at IS NULL AND (is_primary OR is_financial_contact);
  UPDATE public.player_links SET is_primary = (id = p_primary_link), is_financial_contact = (id = p_financial_link)
    WHERE id IN (p_primary_link, p_financial_link);
  PERFORM private.audit(ctx, 'audit', 'player_link.contacts_set', 'player', p_player, NULL,
    jsonb_build_object('before', v_before, 'after', jsonb_build_object('primary', p_primary_link, 'financial', p_financial_link)));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'player_id', p_player));
END;
$$;

-- Price basis: PACKAGE = offer price for its session_count; SESSION = price x
-- purchased sessions, computed once and bounded to numeric(18,2).
CREATE FUNCTION public.purchase_package(p_academy uuid, p_player uuid, p_offer uuid, p_operation_key uuid,
  p_purchased_sessions integer DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; p public.players; o public.service_offers; v_count integer; v_total numeric; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'purchase_package', p_operation_key, jsonb_build_object('player', p_player,
    'offer', p_offer, 'purchased_sessions', p_purchased_sessions));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'packages.purchase');
  p := private.lock_player(p_academy, p_player);
  IF p.deleted_at IS NOT NULL OR p.status = 'INACTIVE' THEN PERFORM private.fail('PLAYER_INACTIVE'); END IF;
  SELECT * INTO o FROM public.service_offers WHERE academy_id = p_academy AND id = p_offer;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF o.status <> 'PUBLISHED' THEN PERFORM private.fail('OFFER_UNAVAILABLE'); END IF;
  IF o.price_basis = 'PACKAGE' THEN
    IF p_purchased_sessions IS NOT NULL AND p_purchased_sessions <> o.session_count THEN
      PERFORM private.fail('INVALID_INPUT', '22023');
    END IF;
    v_count := o.session_count;
    v_total := o.price;
  ELSE
    IF p_purchased_sessions IS NULL OR p_purchased_sessions NOT BETWEEN 1 AND 1000 THEN
      PERFORM private.fail('INVALID_INPUT', '22023');
    END IF;
    v_count := p_purchased_sessions;
    v_total := o.price * p_purchased_sessions;
    IF v_total >= 1e16 THEN PERFORM private.fail('INVALID_AMOUNT', '22023'); END IF;
  END IF;
  INSERT INTO public.player_packages (academy_id, created_by, updated_by, player_id, service_offer_id,
    purchased_sessions, remaining_sessions, total_price, currency, payment_state, status, terms_snapshot, origin)
  VALUES (p_academy, auth.uid(), auth.uid(), p_player, p_offer, v_count, 0, v_total, o.currency, 'PENDING', 'PENDING',
    jsonb_build_object('offer_id', o.id, 'offer_key', o.offer_key, 'version', o.version, 'name', o.name,
      'activity', o.activity, 'session_type', o.session_type, 'min_age', o.min_age, 'max_age', o.max_age,
      'session_count', o.session_count, 'duration_minutes', o.duration_minutes, 'price', o.price::text,
      'currency', o.currency, 'price_basis', o.price_basis, 'purchased_sessions', v_count, 'total_price', v_total::text),
    'PURCHASE')
  RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'package.purchased', 'package', v_id, NULL,
    jsonb_build_object('player_id', p_player, 'offer_id', p_offer, 'total_price', v_total::text, 'currency', o.currency));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'PURCHASED', 'package_id', v_id,
    'total_price', v_total::text, 'currency', o.currency, 'purchased_sessions', v_count));
END;
$$;

-- Credits exist only after a confirmed full payment, or for an explicit free package.
CREATE FUNCTION public.activate_package_credit(p_academy uuid, p_package uuid, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; k public.player_packages;
BEGIN
  ctx := private.cmd_begin(p_academy, 'activate_package_credit', p_operation_key, jsonb_build_object('package', p_package));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'packages.activate_credit');
  k := private.lock_package(p_academy, p_package);
  IF k.status <> 'PENDING' THEN PERFORM private.fail('ALREADY_ACTIVATED'); END IF;
  IF k.total_price > 0 AND k.payment_state <> 'CONFIRMED' THEN PERFORM private.fail('PAYMENT_REQUIRED'); END IF;
  UPDATE public.player_packages SET status = 'ACTIVE', payment_state = 'CONFIRMED',
    acquired_at = transaction_timestamp(), updated_by = auth.uid() WHERE academy_id = p_academy AND id = p_package;
  PERFORM private.ledger_move(ctx, 'ledger', p_package, NULL, k.purchased_sessions, 'PACKAGE_PURCHASE');
  PERFORM private.audit(ctx, 'audit', 'package.activated', 'package', p_package, NULL,
    jsonb_build_object('credits', k.purchased_sessions));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ACTIVATED', 'package_id', p_package,
    'remaining_sessions', k.purchased_sessions, 'confirmed_unconsumed_bookings', 0, 'available_sessions', k.purchased_sessions));
END;
$$;

-- Manual adjustment never makes R negative nor takes a reserved credit (R' >= H).
CREATE FUNCTION public.adjust_course_credit(p_academy uuid, p_package uuid, p_delta integer, p_reason text,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; k public.player_packages; v_reason text; v_h integer;
BEGIN
  ctx := private.cmd_begin(p_academy, 'adjust_course_credit', p_operation_key, jsonb_build_object('package', p_package,
    'delta', p_delta, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'course_ledger.adjust');
  v_reason := private.reason(p_reason, true);
  IF p_delta IS NULL OR p_delta = 0 OR abs(p_delta) > 1000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  k := private.lock_package(p_academy, p_package);
  IF k.status NOT IN ('ACTIVE','EXHAUSTED') THEN PERFORM private.fail('INVALID_STATE'); END IF;
  v_h := private.package_hold(p_academy, p_package);
  IF k.remaining_sessions + p_delta < 0 THEN PERFORM private.fail('NEGATIVE_BALANCE'); END IF;
  IF k.remaining_sessions + p_delta < v_h THEN PERFORM private.fail('RESERVED_CREDIT_CONFLICT'); END IF;
  PERFORM private.ledger_move(ctx, 'ledger', p_package, NULL, p_delta, 'MANUAL_ADJUSTMENT', v_reason);
  PERFORM private.audit(ctx, 'audit', 'package.credit_adjusted', 'package', p_package, v_reason,
    jsonb_build_object('delta', p_delta, 'r_before', k.remaining_sessions, 'h', v_h));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ADJUSTED', 'package_id', p_package,
    'remaining_sessions', k.remaining_sessions + p_delta, 'confirmed_unconsumed_bookings', v_h,
    'available_sessions', k.remaining_sessions + p_delta - v_h));
END;
$$;

CREATE FUNCTION public.archive_package(p_academy uuid, p_package uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; k public.player_packages; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_package', p_operation_key, jsonb_build_object('package', p_package, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'packages.archive');
  v_reason := private.reason(p_reason, true);
  k := private.lock_package(p_academy, p_package);
  IF k.status = 'ARCHIVED' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF EXISTS (SELECT 1 FROM public.bookings b WHERE b.academy_id = p_academy AND b.package_id = p_package
      AND b.status IN ('PENDING','CONFIRMED')) THEN
    PERFORM private.fail('PACKAGE_IN_USE');
  END IF;
  UPDATE public.player_packages SET status = 'ARCHIVED', updated_by = auth.uid() WHERE academy_id = p_academy AND id = p_package;
  PERFORM private.audit(ctx, 'audit', 'package.archived', 'package', p_package, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'package_id', p_package));
END;
$$;

-- Offline payment declared by Owner/Admin; its currency equals the package's.
CREATE FUNCTION public.record_payment(p_academy uuid, p_player uuid, p_package uuid, p_amount text, p_currency text,
  p_method text, p_operation_key uuid, p_external_reference text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; k public.player_packages; v_amount numeric; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'record_payment', p_operation_key, jsonb_build_object('player', p_player,
    'package', p_package, 'amount', p_amount, 'currency', p_currency, 'method', p_method, 'reference', p_external_reference));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'payments.record');
  v_amount := private.money(p_amount, p_currency, false);
  IF p_method IS NULL OR p_method NOT IN ('CASH','CARD','PAYMENT_LINK','BANK_TRANSFER')
     OR length(p_external_reference) > 200 OR (p_package IS NOT NULL AND p_player IS NULL) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  IF p_player IS NOT NULL THEN PERFORM private.lock_player(p_academy, p_player); END IF;
  IF p_package IS NOT NULL THEN
    SELECT * INTO k FROM public.player_packages WHERE academy_id = p_academy AND id = p_package
      AND player_id = p_player FOR UPDATE;
    IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
    IF k.status = 'ARCHIVED' THEN PERFORM private.fail('INVALID_STATE'); END IF;
    IF k.currency <> p_currency THEN PERFORM private.fail('CURRENCY_MISMATCH'); END IF;
  END IF;
  INSERT INTO public.academy_payments (academy_id, player_id, package_id, amount, currency, method, status, origin,
    created_by, external_reference, operation_id)
  VALUES (p_academy, p_player, p_package, v_amount, p_currency, p_method, 'PENDING', 'ADMIN_DECLARATION',
    auth.uid(), nullif(btrim(p_external_reference), ''), (ctx ->> 'operation_id')::uuid)
  RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'payment.recorded', 'payment', v_id, NULL,
    jsonb_build_object('amount', v_amount::text, 'currency', p_currency, 'method', p_method));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'RECORDED', 'payment_id', v_id, 'status', 'PENDING'));
END;
$$;

-- One confirmed payment per package, for exactly its contractual total.
CREATE FUNCTION public.confirm_payment(p_academy uuid, p_payment uuid, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; y public.academy_payments; k public.player_packages;
BEGIN
  ctx := private.cmd_begin(p_academy, 'confirm_payment', p_operation_key, jsonb_build_object('payment', p_payment));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'payments.confirm');
  SELECT * INTO y FROM public.academy_payments WHERE academy_id = p_academy AND id = p_payment;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF y.package_id IS NOT NULL THEN
    k := private.lock_package(p_academy, y.package_id);
  ELSIF y.player_id IS NOT NULL THEN
    PERFORM private.lock_player(p_academy, y.player_id);
  END IF;
  SELECT * INTO y FROM public.academy_payments WHERE id = p_payment FOR UPDATE;
  IF y.status <> 'PENDING' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF y.package_id IS NOT NULL THEN
    IF k.status = 'ARCHIVED' THEN PERFORM private.fail('INVALID_STATE'); END IF;
    IF y.amount <> k.total_price THEN PERFORM private.fail('AMOUNT_MISMATCH'); END IF;
    IF EXISTS (SELECT 1 FROM public.academy_payments x WHERE x.package_id = y.package_id AND x.status = 'CONFIRMED') THEN
      PERFORM private.fail('PAYMENT_ALREADY_CONFIRMED');
    END IF;
    UPDATE public.player_packages SET payment_state = 'CONFIRMED', updated_by = auth.uid()
      WHERE academy_id = p_academy AND id = y.package_id;
  END IF;
  UPDATE public.academy_payments SET status = 'CONFIRMED', confirmed_at = transaction_timestamp(), confirmed_by = auth.uid()
    WHERE id = p_payment;
  PERFORM private.audit(ctx, 'audit', 'payment.confirmed', 'payment', p_payment);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CONFIRMED', 'payment_id', p_payment, 'status', 'CONFIRMED'));
END;
$$;

-- Invoice numbering is supplied by the academy (D32 open); snapshots copy the
-- validated values, they are never a second authority.
CREATE FUNCTION public.issue_invoice(p_academy uuid, p_payment uuid, p_number text, p_operation_key uuid,
  p_description text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  ctx jsonb; y public.academy_payments; a public.academies; p public.players; k public.player_packages;
  v_number text; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'issue_invoice', p_operation_key, jsonb_build_object('payment', p_payment,
    'number', p_number, 'description', p_description));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'invoices.issue');
  v_number := private.require_text(p_number, 100);
  IF length(p_description) > 2000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  SELECT * INTO y FROM public.academy_payments WHERE academy_id = p_academy AND id = p_payment FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF EXISTS (SELECT 1 FROM public.academy_invoices i WHERE i.payment_id = p_payment) THEN
    PERFORM private.fail('ALREADY_INVOICED');
  END IF;
  IF EXISTS (SELECT 1 FROM public.academy_invoices i WHERE i.academy_id = p_academy AND i.number = v_number) THEN
    PERFORM private.fail('INVOICE_NUMBER_TAKEN');
  END IF;
  SELECT * INTO a FROM public.academies WHERE id = p_academy;
  SELECT * INTO p FROM public.players WHERE academy_id = p_academy AND id = y.player_id;
  SELECT * INTO k FROM public.player_packages WHERE academy_id = p_academy AND id = y.package_id;
  BEGIN
    INSERT INTO public.academy_invoices (academy_id, player_id, payment_id, number, issued_at, amount, currency, status,
      source, payment_method, issuer_snapshot, customer_snapshot, player_name_snapshot, description, session_count,
      activity, created_by, operation_id)
    VALUES (p_academy, y.player_id, y.id, v_number, transaction_timestamp(), y.amount, y.currency,
      CASE y.status WHEN 'CONFIRMED' THEN 'PAID' ELSE 'UNPAID' END, 'MANUAL', y.method,
      jsonb_build_object('name', a.name, 'address', a.address, 'city', a.city, 'country', a.country),
      jsonb_strip_nulls(jsonb_build_object('player_id', y.player_id)),
      CASE WHEN p.id IS NOT NULL THEN p.first_name || ' ' || p.last_name END, coalesce(p_description, ''),
      coalesce(k.purchased_sessions, 0), k.terms_snapshot ->> 'activity', auth.uid(), (ctx ->> 'operation_id')::uuid)
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('INVOICE_NUMBER_TAKEN');
  END;
  PERFORM private.audit(ctx, 'audit', 'invoice.issued', 'invoice', v_id, NULL, jsonb_build_object('payment_id', p_payment));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ISSUED', 'invoice_id', v_id, 'number', v_number));
END;
$$;

DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('create_player','update_player_identity','archive_player',
      'assign_player_link','revoke_player_link','set_player_contacts','purchase_package','activate_package_credit',
      'adjust_course_credit','archive_package','record_payment','confirm_payment','issue_invoice') LOOP
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
