-- Phase 3C: memberships/roles, academy and SaaS (platform), sport resources,
-- coaches, versioned offers, sessions, evaluations and tournaments.
-- Role and owner changes serialize on the academy row. Invitation delivery and
-- acceptance belong to 3D (Auth/Edge); here only the durable request is written.

CREATE FUNCTION private.lock_academy(p_academy uuid) RETURNS public.academies
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE a public.academies;
BEGIN
  SELECT * INTO a FROM public.academies WHERE id = p_academy FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  RETURN a;
END;
$$;

-- At least one active owner (active profile, active membership) must remain.
CREATE FUNCTION private.assert_owner_remains(p_academy uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.academy_membership_roles r
      JOIN public.academy_memberships m ON m.academy_id = r.academy_id AND m.id = r.membership_id
      JOIN public.user_profiles u ON u.id = m.user_id
      WHERE r.academy_id = p_academy AND r.role_code = 'ACADEMY_OWNER' AND r.revoked_at IS NULL
        AND m.status = 'ACTIVE' AND u.status = 'ACTIVE') THEN
    PERFORM private.fail('LAST_OWNER');
  END IF;
END;
$$;

CREATE FUNCTION private.validate_roles(p_roles text[]) RETURNS text[]
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF p_roles IS NULL OR array_position(p_roles, NULL) IS NOT NULL
     OR NOT p_roles <@ ARRAY['ACADEMY_OWNER','ACADEMY_ADMIN','MANAGER','STAFF','COACH','STUDENT','PARENT'] THEN
    PERFORM private.fail('INVALID_ROLE', '22023');
  END IF;
  RETURN ARRAY(SELECT DISTINCT r FROM unnest(p_roles) r ORDER BY r);
END;
$$;

CREATE FUNCTION private.validate_invitation(p_email text, p_expires_at timestamptz) RETURNS text
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE v text := lower(btrim(p_email));
BEGIN
  IF v IS NULL OR length(v) > 320 OR position('@' IN v) <= 1 OR v ~ '[[:space:]]' THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  -- The deployment configures expiry; the server only bounds it.
  IF p_expires_at IS NULL OR p_expires_at <= transaction_timestamp()
     OR p_expires_at > transaction_timestamp() + interval '30 days' THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  RETURN v;
END;
$$;

CREATE FUNCTION private.insert_invitation(p_ctx jsonb, p_email text, p_roles text[], p_expires_at timestamptz) RETURNS uuid
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE v_id uuid;
BEGIN
  BEGIN
    INSERT INTO private.academy_invitations (academy_id, email, requested_role_codes, requested_by, status, expires_at, operation_id)
    VALUES ((p_ctx ->> 'academy_id')::uuid, p_email, p_roles, auth.uid(), 'REQUESTED', p_expires_at, (p_ctx ->> 'operation_id')::uuid)
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('INVITATION_EXISTS');
  END;
  PERFORM private.enqueue(p_ctx, 'notify', 'MEMBERSHIP_INVITED', NULL, v_id, jsonb_build_object('invitation_id', v_id));
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.invite_member(p_academy uuid, p_email text, p_roles text[], p_expires_at timestamptz,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_email text; v_roles text[]; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'invite_member', p_operation_key, jsonb_build_object('email', p_email,
    'roles', to_jsonb(p_roles), 'expires_at', p_expires_at));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'memberships.invite');
  v_roles := private.validate_roles(p_roles);
  IF cardinality(v_roles) = 0 THEN PERFORM private.fail('INVALID_ROLE', '22023'); END IF;
  IF 'ACADEMY_OWNER' = ANY (v_roles) THEN PERFORM private.require_permission(p_academy, 'memberships.transfer_owner'); END IF;
  v_email := private.validate_invitation(p_email, p_expires_at);
  PERFORM private.lock_academy(p_academy);
  v_id := private.insert_invitation(ctx, v_email, v_roles, p_expires_at);
  PERFORM private.audit(ctx, 'audit', 'membership.invited', 'invitation', v_id, NULL, jsonb_build_object('roles', to_jsonb(v_roles)));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'INVITED', 'invitation_id', v_id));
END;
$$;

CREATE FUNCTION public.revoke_invitation(p_academy uuid, p_invitation uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; i private.academy_invitations; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'revoke_invitation', p_operation_key, jsonb_build_object('invitation', p_invitation, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'memberships.invite');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO i FROM private.academy_invitations WHERE academy_id = p_academy AND id = p_invitation FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF 'ACADEMY_OWNER' = ANY (i.requested_role_codes) THEN PERFORM private.require_permission(p_academy, 'memberships.transfer_owner'); END IF;
  IF i.status NOT IN ('REQUESTED','PROVISIONING','SENT') THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE private.academy_invitations SET status = 'REVOKED' WHERE id = p_invitation;
  PERFORM private.audit(ctx, 'audit', 'membership.invitation_revoked', 'invitation', p_invitation, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'REVOKED', 'invitation_id', p_invitation));
END;
$$;

-- Fixed roles only. No self change, OWNER only through transfer_owner holders,
-- never the last active owner removed.
CREATE FUNCTION public.set_membership_roles(p_academy uuid, p_membership uuid, p_roles text[], p_reason text,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; m public.academy_memberships; v_roles text[]; v_current text[]; v_added text[]; v_removed text[]; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'set_membership_roles', p_operation_key, jsonb_build_object('membership', p_membership,
    'roles', to_jsonb(p_roles), 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'memberships.set_roles');
  v_roles := private.validate_roles(p_roles);
  v_reason := private.reason(p_reason, true);
  PERFORM private.lock_academy(p_academy);
  SELECT * INTO m FROM public.academy_memberships WHERE academy_id = p_academy AND id = p_membership FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF m.user_id = auth.uid() THEN PERFORM private.fail('SELF_ACTION_FORBIDDEN', '42501'); END IF;
  v_current := ARRAY(SELECT r.role_code FROM private.academy_membership_roles r WHERE r.membership_id = p_membership
    AND r.revoked_at IS NULL ORDER BY r.role_code);
  v_added := ARRAY(SELECT x FROM unnest(v_roles) x EXCEPT SELECT y FROM unnest(v_current) y ORDER BY 1);
  v_removed := ARRAY(SELECT y FROM unnest(v_current) y EXCEPT SELECT x FROM unnest(v_roles) x ORDER BY 1);
  IF 'ACADEMY_OWNER' = ANY (v_added || v_removed) THEN
    PERFORM private.require_permission(p_academy, 'memberships.transfer_owner');
  END IF;
  IF cardinality(v_added) + cardinality(v_removed) = 0 THEN
    RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'NO_CHANGE', 'membership_id', p_membership, 'roles', to_jsonb(v_current)));
  END IF;
  UPDATE private.academy_membership_roles SET revoked_at = transaction_timestamp(), revoked_by = auth.uid()
    WHERE membership_id = p_membership AND revoked_at IS NULL AND role_code = ANY (v_removed);
  INSERT INTO private.academy_membership_roles (academy_id, membership_id, role_code, granted_by)
    SELECT p_academy, p_membership, x, auth.uid() FROM unnest(v_added) x;
  PERFORM private.assert_owner_remains(p_academy);
  PERFORM private.audit(ctx, 'audit', 'membership.roles_set', 'membership', p_membership, v_reason,
    jsonb_build_object('before', to_jsonb(v_current), 'after', to_jsonb(v_roles)));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'membership_id', p_membership, 'roles', to_jsonb(v_roles)));
END;
$$;

CREATE FUNCTION private.set_membership_status(p_ctx jsonb, p_membership uuid, p_from text, p_to text, p_reason text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE v_academy uuid := (p_ctx ->> 'academy_id')::uuid; m public.academy_memberships;
BEGIN
  PERFORM private.require_permission(v_academy, 'memberships.suspend');
  PERFORM private.lock_academy(v_academy);
  SELECT * INTO m FROM public.academy_memberships WHERE academy_id = v_academy AND id = p_membership FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF m.user_id = auth.uid() THEN PERFORM private.fail('SELF_ACTION_FORBIDDEN', '42501'); END IF;
  IF EXISTS (SELECT 1 FROM private.academy_membership_roles r WHERE r.membership_id = p_membership
      AND r.revoked_at IS NULL AND r.role_code = 'ACADEMY_OWNER') THEN
    PERFORM private.require_permission(v_academy, 'memberships.transfer_owner');
  END IF;
  IF m.status <> p_from THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE public.academy_memberships SET status = p_to, updated_by = auth.uid(),
    joined_at = coalesce(joined_at, CASE WHEN p_to = 'ACTIVE' THEN transaction_timestamp() END)
  WHERE id = p_membership;
  PERFORM private.assert_owner_remains(v_academy);
  PERFORM private.audit(p_ctx, 'audit', CASE p_to WHEN 'SUSPENDED' THEN 'membership.suspended' ELSE 'membership.reactivated' END,
    'membership', p_membership, p_reason);
END;
$$;

CREATE FUNCTION public.suspend_membership(p_academy uuid, p_membership uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'suspend_membership', p_operation_key, jsonb_build_object('membership', p_membership, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.set_membership_status(ctx, p_membership, 'ACTIVE', 'SUSPENDED', private.reason(p_reason, true));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'SUSPENDED', 'membership_id', p_membership));
END;
$$;

CREATE FUNCTION public.reactivate_membership(p_academy uuid, p_membership uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'reactivate_membership', p_operation_key, jsonb_build_object('membership', p_membership, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.set_membership_status(ctx, p_membership, 'SUSPENDED', 'ACTIVE', private.reason(p_reason, true));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'REACTIVATED', 'membership_id', p_membership));
END;
$$;

CREATE FUNCTION public.transfer_ownership(p_academy uuid, p_target_membership uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; m public.academy_memberships; v_reason text; v_mine uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'transfer_ownership', p_operation_key, jsonb_build_object('membership', p_target_membership, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'memberships.transfer_owner');
  v_reason := private.reason(p_reason, true);
  PERFORM private.lock_academy(p_academy);
  SELECT * INTO m FROM public.academy_memberships WHERE academy_id = p_academy AND id = p_target_membership FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF m.user_id = auth.uid() THEN PERFORM private.fail('SELF_ACTION_FORBIDDEN', '42501'); END IF;
  IF m.status <> 'ACTIVE' OR NOT EXISTS (SELECT 1 FROM public.user_profiles u WHERE u.id = m.user_id AND u.status = 'ACTIVE') THEN
    PERFORM private.fail('INVALID_STATE');
  END IF;
  SELECT id INTO v_mine FROM public.academy_memberships WHERE academy_id = p_academy AND user_id = auth.uid();
  IF NOT EXISTS (SELECT 1 FROM private.academy_membership_roles r WHERE r.membership_id = p_target_membership
      AND r.revoked_at IS NULL AND r.role_code = 'ACADEMY_OWNER') THEN
    INSERT INTO private.academy_membership_roles (academy_id, membership_id, role_code, granted_by)
    VALUES (p_academy, p_target_membership, 'ACADEMY_OWNER', auth.uid());
  END IF;
  UPDATE private.academy_membership_roles SET revoked_at = transaction_timestamp(), revoked_by = auth.uid()
    WHERE membership_id = v_mine AND role_code = 'ACADEMY_OWNER' AND revoked_at IS NULL;
  PERFORM private.assert_owner_remains(p_academy);
  PERFORM private.audit(ctx, 'audit', 'membership.ownership_transferred', 'membership', p_target_membership, v_reason,
    jsonb_build_object('from_membership', v_mine));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'TRANSFERRED', 'membership_id', p_target_membership));
END;
$$;

-- Platform: the academy and its first-owner invitation form one tenant operation.
CREATE FUNCTION public.create_academy(p_name text, p_city text, p_country text, p_timezone text, p_language text,
  p_owner_email text, p_invitation_expires_at timestamptz, p_operation_key uuid, p_address text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_email text; v_id uuid; v_invitation uuid;
BEGIN
  ctx := private.cmd_begin(NULL, 'create_academy', p_operation_key, jsonb_build_object('name', p_name, 'city', p_city,
    'country', p_country, 'timezone', p_timezone, 'language', p_language, 'owner_email', p_owner_email,
    'expires_at', p_invitation_expires_at, 'address', p_address), true);
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_platform_permission('academies.create');
  IF p_language IS NULL OR p_language NOT IN ('FR','EN') OR length(p_address) > 500
     OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  v_email := private.validate_invitation(p_owner_email, p_invitation_expires_at);
  INSERT INTO public.academies (created_by, updated_by, name, city, country, address, timezone, default_language, status)
  VALUES (auth.uid(), auth.uid(), private.require_text(p_name, 160), private.require_text(p_city, 160),
    private.require_text(p_country, 160), nullif(btrim(p_address), ''), p_timezone, p_language, 'ACTIVE')
  RETURNING id INTO v_id;
  ctx := ctx || jsonb_build_object('academy_id', v_id);
  v_invitation := private.insert_invitation(ctx, v_email, ARRAY['ACADEMY_OWNER'], p_invitation_expires_at);
  PERFORM private.audit(ctx, 'audit', 'academy.created', 'academy', v_id, NULL, jsonb_build_object('invitation_id', v_invitation));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'academy_id', v_id, 'invitation_id', v_invitation));
END;
$$;

CREATE FUNCTION public.update_academy(p_academy uuid, p_operation_key uuid, p_name text DEFAULT NULL, p_city text DEFAULT NULL,
  p_country text DEFAULT NULL, p_address text DEFAULT NULL, p_timezone text DEFAULT NULL, p_language text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; a public.academies;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_academy', p_operation_key, jsonb_build_object('name', p_name, 'city', p_city,
    'country', p_country, 'address', p_address, 'timezone', p_timezone, 'language', p_language));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'academy.update');
  IF (p_language IS NOT NULL AND p_language NOT IN ('FR','EN')) OR length(p_address) > 500
     OR (p_timezone IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone)) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  a := private.lock_academy(p_academy);
  UPDATE public.academies SET updated_by = auth.uid(),
    name = CASE WHEN p_name IS NULL THEN name ELSE private.require_text(p_name, 160) END,
    city = CASE WHEN p_city IS NULL THEN city ELSE private.require_text(p_city, 160) END,
    country = CASE WHEN p_country IS NULL THEN country ELSE private.require_text(p_country, 160) END,
    address = coalesce(p_address, address), timezone = coalesce(p_timezone, timezone),
    default_language = coalesce(p_language, default_language)
  WHERE id = p_academy;
  PERFORM private.audit(ctx, 'audit', 'academy.updated', 'academy', p_academy);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'academy_id', p_academy));
END;
$$;

CREATE FUNCTION public.set_academy_status(p_academy uuid, p_status text, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; a public.academies; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'set_academy_status', p_operation_key, jsonb_build_object('status', p_status, 'reason', p_reason), true);
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_platform_permission('academies.set_status');
  v_reason := private.reason(p_reason, true);
  IF p_status IS NULL OR p_status NOT IN ('ACTIVE','SUSPENDED','ARCHIVED') THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  a := private.lock_academy(p_academy);
  IF a.status = 'ARCHIVED' OR a.status = p_status THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE public.academies SET status = p_status, updated_by = auth.uid() WHERE id = p_academy;
  PERFORM private.audit(ctx, 'audit', 'academy.status_set', 'academy', p_academy, v_reason,
    jsonb_build_object('before', a.status, 'after', p_status));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'academy_id', p_academy, 'status', p_status));
END;
$$;

-- Plans are catalogue entries only: no price or quota is stored or invented.
CREATE FUNCTION public.create_plan(p_code text, p_version integer, p_name text, p_operation_key uuid,
  p_description text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid;
BEGIN
  ctx := private.cmd_begin(NULL, 'create_plan', p_operation_key, jsonb_build_object('code', p_code, 'version', p_version,
    'name', p_name, 'description', p_description), true);
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_platform_permission('plans.write');
  IF p_version IS NULL OR p_version < 1 OR length(p_description) > 2000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  BEGIN
    INSERT INTO public.platform_plans (code, version, name, description)
    VALUES (private.require_text(p_code, 100), p_version, private.require_text(p_name, 160), coalesce(p_description, ''))
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('PLAN_EXISTS');
  END;
  PERFORM private.audit(ctx, 'audit', 'plan.created', 'plan', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'plan_id', v_id));
END;
$$;

CREATE FUNCTION public.set_plan_active(p_plan uuid, p_active boolean, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(NULL, 'set_plan_active', p_operation_key, jsonb_build_object('plan', p_plan, 'active', p_active), true);
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_platform_permission('plans.write');
  IF p_active IS NULL THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  UPDATE public.platform_plans SET active = p_active WHERE id = p_plan;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'plan.active_set', 'plan', p_plan, NULL, jsonb_build_object('active', p_active));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'plan_id', p_plan, 'active', p_active));
END;
$$;

CREATE FUNCTION private.subscription_event(p_ctx jsonb, p_subscription uuid, p_type text, p_before text, p_after text,
  p_reason text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  INSERT INTO private.subscription_events (academy_id, operation_id, effect_key, actor_kind, actor_user_id, actor_ref,
    subscription_id, event_type, before_status, after_status, effective_at, reason, metadata)
  VALUES ((p_ctx ->> 'academy_id')::uuid, (p_ctx ->> 'operation_id')::uuid, 'event', 'USER', auth.uid(), auth.uid()::text,
    p_subscription, p_type, p_before, p_after, transaction_timestamp(), p_reason, p_metadata);
$$;

-- Manual SaaS lifecycle; trial length is an explicit date (D17), never a default.
CREATE FUNCTION public.create_subscription(p_academy uuid, p_plan uuid, p_status text, p_starts_at timestamptz,
  p_reason text, p_operation_key uuid, p_trial_ends_at timestamptz DEFAULT NULL, p_ends_at timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_subscription', p_operation_key, jsonb_build_object('plan', p_plan,
    'status', p_status, 'starts_at', p_starts_at, 'trial_ends_at', p_trial_ends_at, 'ends_at', p_ends_at, 'reason', p_reason), true);
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_platform_permission('subscriptions.transition');
  v_reason := private.reason(p_reason, true);
  IF p_status IS NULL OR p_status NOT IN ('TRIALING','ACTIVE') OR p_starts_at IS NULL OR NOT isfinite(p_starts_at)
     OR (p_status = 'TRIALING' AND (p_trial_ends_at IS NULL OR p_trial_ends_at <= p_starts_at))
     OR (p_ends_at IS NOT NULL AND p_ends_at <= p_starts_at) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  PERFORM private.lock_academy(p_academy);
  IF NOT EXISTS (SELECT 1 FROM public.platform_plans p WHERE p.id = p_plan AND p.active) THEN
    PERFORM private.fail('PLAN_INACTIVE');
  END IF;
  IF EXISTS (SELECT 1 FROM public.academy_subscriptions s WHERE s.academy_id = p_academy
      AND s.status IN ('TRIALING','ACTIVE','SUSPENDED')) THEN
    PERFORM private.fail('SUBSCRIPTION_EXISTS');
  END IF;
  INSERT INTO public.academy_subscriptions (academy_id, plan_id, status, starts_at, ends_at, trial_ends_at)
  VALUES (p_academy, p_plan, p_status, p_starts_at, p_ends_at, p_trial_ends_at) RETURNING id INTO v_id;
  PERFORM private.subscription_event(ctx, v_id, 'CREATED', NULL, p_status, v_reason, jsonb_build_object('plan_id', p_plan));
  PERFORM private.audit(ctx, 'audit', 'subscription.created', 'subscription', v_id, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'subscription_id', v_id, 'status', p_status, 'revision', 1));
END;
$$;

-- Status only: the effects of a commercial suspension on tenant operations (D32) are not enforced.
CREATE FUNCTION public.transition_subscription(p_academy uuid, p_subscription uuid, p_status text, p_expected_revision bigint,
  p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; s public.academy_subscriptions; v_reason text; v_event text; v_before text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'transition_subscription', p_operation_key, jsonb_build_object('subscription', p_subscription,
    'status', p_status, 'revision', p_expected_revision, 'reason', p_reason), true);
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_platform_permission('subscriptions.transition');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO s FROM public.academy_subscriptions WHERE academy_id = p_academy AND id = p_subscription FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.check_revision(s.revision, p_expected_revision);
  v_event := CASE
    WHEN s.status = 'TRIALING' AND p_status = 'ACTIVE' THEN 'ACTIVATED'
    WHEN s.status = 'SUSPENDED' AND p_status = 'ACTIVE' THEN 'RESUMED'
    WHEN s.status IN ('TRIALING','ACTIVE') AND p_status = 'SUSPENDED' THEN 'SUSPENDED'
    WHEN s.status IN ('TRIALING','ACTIVE','SUSPENDED') AND p_status = 'CANCELLED' THEN 'CANCELLED'
    WHEN s.status IN ('TRIALING','ACTIVE','SUSPENDED') AND p_status = 'EXPIRED' THEN 'EXPIRED' END;
  IF v_event IS NULL THEN PERFORM private.fail('INVALID_STATE'); END IF;
  v_before := s.status;
  UPDATE public.academy_subscriptions SET status = p_status, revision = revision + 1 WHERE id = p_subscription RETURNING * INTO s;
  PERFORM private.subscription_event(ctx, p_subscription, v_event, v_before, p_status, v_reason);
  PERFORM private.audit(ctx, 'audit', 'subscription.' || lower(v_event), 'subscription', p_subscription, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', v_event, 'subscription_id', p_subscription,
    'status', p_status, 'revision', s.revision));
END;
$$;

-- Sport resources. Archiving is refused while a future OPEN/CLOSED session or an
-- active child resource depends on it; names are unique among live rows.
CREATE FUNCTION private.resource_in_use(p_academy uuid, p_kind text, p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT CASE p_kind
    WHEN 'stadium' THEN EXISTS (SELECT 1 FROM public.courts c WHERE c.academy_id = p_academy AND c.stadium_id = p_id AND c.deleted_at IS NULL)
      OR EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy AND s.stadium_id = p_id
        AND s.status IN ('OPEN','CLOSED') AND s.ends_at > transaction_timestamp())
    WHEN 'court' THEN EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy AND s.court_id = p_id
        AND s.status IN ('OPEN','CLOSED') AND s.ends_at > transaction_timestamp())
    WHEN 'community' THEN EXISTS (SELECT 1 FROM public.community_courses c WHERE c.academy_id = p_academy
        AND c.community_id = p_id AND c.deleted_at IS NULL)
    WHEN 'coach' THEN EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy AND s.coach_id = p_id
        AND s.status IN ('OPEN','CLOSED') AND s.ends_at > transaction_timestamp())
    ELSE false END;
$$;

CREATE FUNCTION public.create_stadium(p_academy uuid, p_name text, p_address text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_stadium', p_operation_key, jsonb_build_object('name', p_name, 'address', p_address));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'stadiums.create');
  IF p_address IS NULL OR length(p_address) > 500 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  INSERT INTO public.stadiums (academy_id, created_by, updated_by, name, address)
  VALUES (p_academy, auth.uid(), auth.uid(), private.require_text(p_name, 160), btrim(p_address)) RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'stadium.created', 'stadium', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'stadium_id', v_id));
END;
$$;

CREATE FUNCTION public.update_stadium(p_academy uuid, p_stadium uuid, p_operation_key uuid, p_name text DEFAULT NULL,
  p_address text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_stadium', p_operation_key, jsonb_build_object('stadium', p_stadium, 'name', p_name, 'address', p_address));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'stadiums.update');
  IF length(p_address) > 500 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  UPDATE public.stadiums SET updated_by = auth.uid(), address = coalesce(btrim(p_address), address),
    name = CASE WHEN p_name IS NULL THEN name ELSE private.require_text(p_name, 160) END
  WHERE academy_id = p_academy AND id = p_stadium AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'stadium.updated', 'stadium', p_stadium);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'stadium_id', p_stadium));
END;
$$;

CREATE FUNCTION public.archive_stadium(p_academy uuid, p_stadium uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_stadium', p_operation_key, jsonb_build_object('stadium', p_stadium, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'stadiums.archive');
  v_reason := private.reason(p_reason, true);
  PERFORM 1 FROM public.stadiums WHERE academy_id = p_academy AND id = p_stadium AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF private.resource_in_use(p_academy, 'stadium', p_stadium) THEN PERFORM private.fail('RESOURCE_IN_USE'); END IF;
  UPDATE public.stadiums SET active = false, deleted_at = transaction_timestamp(), deleted_by = auth.uid(), updated_by = auth.uid()
    WHERE id = p_stadium;
  PERFORM private.audit(ctx, 'audit', 'stadium.archived', 'stadium', p_stadium, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'stadium_id', p_stadium));
END;
$$;

CREATE FUNCTION public.create_court(p_academy uuid, p_stadium uuid, p_number integer, p_operation_key uuid,
  p_label text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_court', p_operation_key, jsonb_build_object('stadium', p_stadium,
    'number', p_number, 'label', p_label));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'courts.create');
  IF p_number IS NULL OR p_number NOT BETWEEN 1 AND 100 OR length(p_label) > 100 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  PERFORM 1 FROM public.stadiums WHERE academy_id = p_academy AND id = p_stadium AND active AND deleted_at IS NULL FOR SHARE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  BEGIN
    INSERT INTO public.courts (academy_id, created_by, updated_by, stadium_id, number, label)
    VALUES (p_academy, auth.uid(), auth.uid(), p_stadium, p_number, nullif(btrim(p_label), '')) RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('NAME_TAKEN');
  END;
  PERFORM private.audit(ctx, 'audit', 'court.created', 'court', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'court_id', v_id));
END;
$$;

CREATE FUNCTION public.update_court(p_academy uuid, p_court uuid, p_label text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_court', p_operation_key, jsonb_build_object('court', p_court, 'label', p_label));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'courts.update');
  IF length(p_label) > 100 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  UPDATE public.courts SET label = nullif(btrim(p_label), ''), updated_by = auth.uid()
    WHERE academy_id = p_academy AND id = p_court AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'court.updated', 'court', p_court);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'court_id', p_court));
END;
$$;

CREATE FUNCTION public.archive_court(p_academy uuid, p_court uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_court', p_operation_key, jsonb_build_object('court', p_court, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'courts.archive');
  v_reason := private.reason(p_reason, true);
  PERFORM 1 FROM public.courts WHERE academy_id = p_academy AND id = p_court AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF private.resource_in_use(p_academy, 'court', p_court) THEN PERFORM private.fail('RESOURCE_IN_USE'); END IF;
  UPDATE public.courts SET active = false, deleted_at = transaction_timestamp(), deleted_by = auth.uid(), updated_by = auth.uid()
    WHERE id = p_court;
  PERFORM private.audit(ctx, 'audit', 'court.archived', 'court', p_court, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'court_id', p_court));
END;
$$;

CREATE FUNCTION public.create_community(p_academy uuid, p_name text, p_operation_key uuid, p_description text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_community', p_operation_key, jsonb_build_object('name', p_name, 'description', p_description));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'communities.create');
  IF length(p_description) > 1000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  BEGIN
    INSERT INTO public.communities (academy_id, created_by, updated_by, name, description)
    VALUES (p_academy, auth.uid(), auth.uid(), private.require_text(p_name, 160), coalesce(p_description, '')) RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('NAME_TAKEN');
  END;
  PERFORM private.audit(ctx, 'audit', 'community.created', 'community', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'community_id', v_id));
END;
$$;

CREATE FUNCTION public.update_community(p_academy uuid, p_community uuid, p_operation_key uuid, p_name text DEFAULT NULL,
  p_description text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_community', p_operation_key, jsonb_build_object('community', p_community,
    'name', p_name, 'description', p_description));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'communities.update');
  IF length(p_description) > 1000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  BEGIN
    UPDATE public.communities SET updated_by = auth.uid(), description = coalesce(p_description, description),
      name = CASE WHEN p_name IS NULL THEN name ELSE private.require_text(p_name, 160) END
    WHERE academy_id = p_academy AND id = p_community AND deleted_at IS NULL;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('NAME_TAKEN');
  END;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'community.updated', 'community', p_community);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'community_id', p_community));
END;
$$;

CREATE FUNCTION public.archive_community(p_academy uuid, p_community uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_community', p_operation_key, jsonb_build_object('community', p_community, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'communities.archive');
  v_reason := private.reason(p_reason, true);
  PERFORM 1 FROM public.communities WHERE academy_id = p_academy AND id = p_community AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF private.resource_in_use(p_academy, 'community', p_community) THEN PERFORM private.fail('RESOURCE_IN_USE'); END IF;
  UPDATE public.communities SET active = false, deleted_at = transaction_timestamp(), deleted_by = auth.uid(), updated_by = auth.uid()
    WHERE id = p_community;
  PERFORM private.audit(ctx, 'audit', 'community.archived', 'community', p_community, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'community_id', p_community));
END;
$$;

CREATE FUNCTION public.create_community_course(p_academy uuid, p_community uuid, p_name text, p_operation_key uuid,
  p_description text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_community_course', p_operation_key, jsonb_build_object('community', p_community,
    'name', p_name, 'description', p_description));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'community_courses.create');
  IF length(p_description) > 500 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  PERFORM 1 FROM public.communities WHERE academy_id = p_academy AND id = p_community AND active AND deleted_at IS NULL FOR SHARE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  BEGIN
    INSERT INTO public.community_courses (academy_id, created_by, updated_by, community_id, name, description)
    VALUES (p_academy, auth.uid(), auth.uid(), p_community, private.require_text(p_name, 160), coalesce(p_description, ''))
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('NAME_TAKEN');
  END;
  PERFORM private.audit(ctx, 'audit', 'community_course.created', 'community_course', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'community_course_id', v_id));
END;
$$;

CREATE FUNCTION public.update_community_course(p_academy uuid, p_course uuid, p_operation_key uuid, p_name text DEFAULT NULL,
  p_description text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_community_course', p_operation_key, jsonb_build_object('course', p_course,
    'name', p_name, 'description', p_description));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'community_courses.update');
  IF length(p_description) > 500 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  BEGIN
    UPDATE public.community_courses SET updated_by = auth.uid(), description = coalesce(p_description, description),
      name = CASE WHEN p_name IS NULL THEN name ELSE private.require_text(p_name, 160) END
    WHERE academy_id = p_academy AND id = p_course AND deleted_at IS NULL;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('NAME_TAKEN');
  END;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'community_course.updated', 'community_course', p_course);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'community_course_id', p_course));
END;
$$;

CREATE FUNCTION public.archive_community_course(p_academy uuid, p_course uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_community_course', p_operation_key, jsonb_build_object('course', p_course, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'community_courses.archive');
  v_reason := private.reason(p_reason, true);
  UPDATE public.community_courses SET active = false, deleted_at = transaction_timestamp(), deleted_by = auth.uid(),
    updated_by = auth.uid() WHERE academy_id = p_academy AND id = p_course AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'community_course.archived', 'community_course', p_course, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'community_course_id', p_course));
END;
$$;

-- A coach record attaches to an existing ACTIVE membership that already holds
-- COACH; creating/inviting that membership or changing roles is Owner/Admin only.
CREATE FUNCTION public.create_coach(p_academy uuid, p_membership uuid, p_operation_key uuid, p_specialties text[] DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid; v_specialties text[] := coalesce(p_specialties, '{}');
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_coach', p_operation_key, jsonb_build_object('membership', p_membership,
    'specialties', to_jsonb(v_specialties)));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'coaches.create');
  IF cardinality(v_specialties) > 20 OR EXISTS (SELECT 1 FROM unnest(v_specialties) x WHERE x IS NULL OR length(btrim(x)) NOT BETWEEN 1 AND 60) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  PERFORM 1 FROM public.academy_memberships m WHERE m.academy_id = p_academy AND m.id = p_membership AND m.status = 'ACTIVE' FOR SHARE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF NOT EXISTS (SELECT 1 FROM private.academy_membership_roles r WHERE r.membership_id = p_membership
      AND r.role_code = 'COACH' AND r.revoked_at IS NULL) THEN
    PERFORM private.fail('COACH_ROLE_REQUIRED');
  END IF;
  BEGIN
    INSERT INTO public.coaches (academy_id, created_by, updated_by, membership_id, specialties)
    VALUES (p_academy, auth.uid(), auth.uid(), p_membership, v_specialties) RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    PERFORM private.fail('COACH_EXISTS');
  END;
  PERFORM private.audit(ctx, 'audit', 'coach.created', 'coach', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'coach_id', v_id));
END;
$$;

CREATE FUNCTION public.archive_coach(p_academy uuid, p_coach uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_coach', p_operation_key, jsonb_build_object('coach', p_coach, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'coaches.archive');
  v_reason := private.reason(p_reason, true);
  PERFORM 1 FROM public.coaches WHERE academy_id = p_academy AND id = p_coach AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  IF private.resource_in_use(p_academy, 'coach', p_coach) THEN PERFORM private.fail('COACH_IN_USE'); END IF;
  UPDATE public.coaches SET active = false, deleted_at = transaction_timestamp(), deleted_by = auth.uid(), updated_by = auth.uid()
    WHERE id = p_coach;
  PERFORM private.audit(ctx, 'audit', 'coach.archived', 'coach', p_coach, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'coach_id', p_coach));
END;
$$;

-- Versioned offers. A series (academy, offer_key) is serialized by an advisory
-- lock; publishing retires the current version and publishes the draft atomically.
CREATE FUNCTION private.lock_offer_series(p_academy uuid, p_offer_key uuid) RETURNS void
LANGUAGE sql SET search_path = pg_catalog AS $$
  SELECT pg_advisory_xact_lock(hashtextextended('offer/' || p_academy::text || '/' || p_offer_key::text, 0));
$$;

CREATE FUNCTION public.create_offer(p_academy uuid, p_name text, p_activity text, p_session_type text, p_min_age integer,
  p_max_age integer, p_session_count integer, p_price text, p_currency text, p_price_basis text, p_operation_key uuid,
  p_duration_minutes integer DEFAULT NULL, p_offer_key uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_price numeric; v_key uuid := coalesce(p_offer_key, gen_random_uuid()); v_prev public.service_offers; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_offer', p_operation_key, jsonb_build_object('name', p_name, 'activity', p_activity,
    'session_type', p_session_type, 'min_age', p_min_age, 'max_age', p_max_age, 'session_count', p_session_count,
    'price', p_price, 'currency', p_currency, 'price_basis', p_price_basis, 'duration', p_duration_minutes, 'offer_key', p_offer_key));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'service_offers.create');
  IF p_price_basis IS NULL THEN PERFORM private.fail('PRICE_BASIS_REQUIRED', '22023'); END IF;
  IF p_price_basis NOT IN ('PACKAGE','SESSION') OR p_activity IS NULL OR p_activity NOT IN ('TENNIS','PADEL')
     OR p_session_type IS NULL OR p_session_type NOT IN ('PRIVATE','SEMI_PRIVATE','GROUP')
     OR p_min_age IS NULL OR p_max_age IS NULL OR p_min_age NOT BETWEEN 2 AND 100 OR p_max_age NOT BETWEEN 2 AND 100
     OR p_min_age > p_max_age OR p_session_count IS NULL OR p_session_count NOT BETWEEN 1 AND 1000
     OR (p_duration_minutes IS NOT NULL AND p_duration_minutes NOT BETWEEN 15 AND 480) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  v_price := private.money(p_price, p_currency, true);
  PERFORM private.lock_offer_series(p_academy, v_key);
  SELECT * INTO v_prev FROM public.service_offers WHERE academy_id = p_academy AND offer_key = v_key
    ORDER BY version DESC LIMIT 1;
  IF p_offer_key IS NOT NULL AND v_prev.id IS NULL THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  INSERT INTO public.service_offers (academy_id, created_by, updated_by, offer_key, version, supersedes_id, name, activity,
    session_type, min_age, max_age, session_count, price, currency, price_basis, duration_minutes, status)
  VALUES (p_academy, auth.uid(), auth.uid(), v_key, coalesce(v_prev.version, 0) + 1, v_prev.id,
    private.require_text(p_name, 160), p_activity, p_session_type, p_min_age, p_max_age, p_session_count, v_price,
    p_currency, p_price_basis, p_duration_minutes, 'DRAFT')
  RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'offer.created', 'offer', v_id, NULL,
    jsonb_build_object('offer_key', v_key, 'version', coalesce(v_prev.version, 0) + 1));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'offer_id', v_id, 'offer_key', v_key,
    'version', coalesce(v_prev.version, 0) + 1));
END;
$$;

CREATE FUNCTION public.publish_offer(p_academy uuid, p_offer uuid, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; o public.service_offers; v_retired uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'publish_offer', p_operation_key, jsonb_build_object('offer', p_offer));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'service_offers.publish');
  SELECT * INTO o FROM public.service_offers WHERE academy_id = p_academy AND id = p_offer;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.lock_offer_series(p_academy, o.offer_key);
  SELECT * INTO o FROM public.service_offers WHERE id = p_offer FOR UPDATE;
  IF o.status <> 'DRAFT' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE public.service_offers SET status = 'RETIRED', retired_at = transaction_timestamp(), updated_by = auth.uid()
    WHERE academy_id = p_academy AND offer_key = o.offer_key AND status = 'PUBLISHED' RETURNING id INTO v_retired;
  UPDATE public.service_offers SET status = 'PUBLISHED', published_at = transaction_timestamp(), updated_by = auth.uid()
    WHERE id = p_offer;
  PERFORM private.audit(ctx, 'audit', 'offer.published', 'offer', p_offer, NULL, jsonb_build_object('retired', v_retired));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'PUBLISHED', 'offer_id', p_offer, 'retired_offer_id', v_retired));
END;
$$;

CREATE FUNCTION public.retire_offer(p_academy uuid, p_offer uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; o public.service_offers; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'retire_offer', p_operation_key, jsonb_build_object('offer', p_offer, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'service_offers.retire');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO o FROM public.service_offers WHERE academy_id = p_academy AND id = p_offer;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.lock_offer_series(p_academy, o.offer_key);
  SELECT * INTO o FROM public.service_offers WHERE id = p_offer FOR UPDATE;
  IF o.status = 'RETIRED' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE public.service_offers SET status = 'RETIRED', retired_at = transaction_timestamp(), updated_by = auth.uid() WHERE id = p_offer;
  PERFORM private.audit(ctx, 'audit', 'offer.retired', 'offer', p_offer, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'RETIRED', 'offer_id', p_offer));
END;
$$;

-- Court and local coach double-booking are arbitrated by the exclusion
-- constraints at write time (not "check then insert").
CREATE FUNCTION public.create_session(p_academy uuid, p_offer uuid, p_coach uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_capacity integer, p_operation_key uuid, p_stadium uuid DEFAULT NULL, p_court uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_stadium uuid := p_stadium; v_id uuid; v_constraint text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_session', p_operation_key, jsonb_build_object('offer', p_offer, 'coach', p_coach,
    'starts_at', p_starts_at, 'ends_at', p_ends_at, 'capacity', p_capacity, 'stadium', p_stadium, 'court', p_court));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'sessions.create');
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR NOT isfinite(p_starts_at) OR NOT isfinite(p_ends_at)
     OR p_starts_at <= transaction_timestamp() OR p_ends_at <= p_starts_at OR p_ends_at - p_starts_at > interval '8 hours'
     OR p_capacity IS NULL OR p_capacity NOT BETWEEN 1 AND 100 THEN
    PERFORM private.fail('INVALID_SESSION', '22023');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_offers o WHERE o.academy_id = p_academy AND o.id = p_offer AND o.status = 'PUBLISHED') THEN
    PERFORM private.fail('OFFER_UNAVAILABLE');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.coaches c JOIN public.academy_memberships m ON m.academy_id = c.academy_id AND m.id = c.membership_id
      JOIN private.academy_membership_roles r ON r.membership_id = m.id AND r.role_code = 'COACH' AND r.revoked_at IS NULL
      WHERE c.academy_id = p_academy AND c.id = p_coach AND c.active AND c.deleted_at IS NULL AND m.status = 'ACTIVE') THEN
    PERFORM private.fail('COACH_UNAVAILABLE');
  END IF;
  IF p_court IS NOT NULL THEN
    SELECT c.stadium_id INTO v_stadium FROM public.courts c WHERE c.academy_id = p_academy AND c.id = p_court
      AND c.active AND c.deleted_at IS NULL AND (p_stadium IS NULL OR c.stadium_id = p_stadium);
    IF v_stadium IS NULL THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  END IF;
  IF v_stadium IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.stadiums s WHERE s.academy_id = p_academy AND s.id = v_stadium
      AND s.active AND s.deleted_at IS NULL) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  BEGIN
    INSERT INTO public.sessions (academy_id, created_by, updated_by, service_offer_id, coach_id, stadium_id, court_id,
      starts_at, ends_at, capacity, status)
    VALUES (p_academy, auth.uid(), auth.uid(), p_offer, p_coach, v_stadium, p_court, p_starts_at, p_ends_at, p_capacity, 'OPEN')
    RETURNING id INTO v_id;
  EXCEPTION WHEN exclusion_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    PERFORM private.fail(CASE v_constraint WHEN 'sessions_court_no_overlap' THEN 'COURT_CONFLICT' ELSE 'COACH_CONFLICT' END);
  END;
  PERFORM private.audit(ctx, 'audit', 'session.created', 'session', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'session_id', v_id, 'revision', 1));
END;
$$;

-- CLOSED ends enrolment and still blocks court and coach.
CREATE FUNCTION public.close_session(p_academy uuid, p_session uuid, p_expected_revision bigint, p_reason text,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; s public.sessions; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'close_session', p_operation_key, jsonb_build_object('session', p_session,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'sessions.close');
  v_reason := private.reason(p_reason, true);
  SELECT * INTO s FROM public.sessions WHERE academy_id = p_academy AND id = p_session FOR UPDATE;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.check_revision(s.revision, p_expected_revision);
  IF s.status <> 'OPEN' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  UPDATE public.sessions SET status = 'CLOSED', revision = revision + 1, updated_by = auth.uid() WHERE id = p_session RETURNING * INTO s;
  PERFORM private.audit(ctx, 'audit', 'session.closed', 'session', p_session, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CLOSED', 'session_id', p_session, 'revision', s.revision));
END;
$$;

-- Cancels every active booking of the session in canonical lock order, in one
-- bounded atomic batch; confirmed holds are released without ledger movement.
CREATE FUNCTION public.cancel_session(p_academy uuid, p_session uuid, p_expected_revision bigint, p_reason text,
  p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; s public.sessions; v_reason text; v_booking uuid; v_count integer := 0;
BEGIN
  ctx := private.cmd_begin(p_academy, 'cancel_session', p_operation_key, jsonb_build_object('session', p_session,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'sessions.cancel');
  v_reason := private.reason(p_reason, true);
  IF NOT EXISTS (SELECT 1 FROM public.sessions WHERE academy_id = p_academy AND id = p_session) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  IF (SELECT count(*) FROM public.bookings b WHERE b.academy_id = p_academy AND b.session_id = p_session
      AND b.status IN ('PENDING','CONFIRMED')) > 200 THEN
    PERFORM private.fail('TOO_MANY_BOOKINGS');
  END IF;
  PERFORM 1 FROM public.players p WHERE p.academy_id = p_academy AND p.id IN (SELECT b.player_id FROM public.bookings b
    WHERE b.academy_id = p_academy AND b.session_id = p_session AND b.status IN ('PENDING','CONFIRMED')) ORDER BY p.id FOR UPDATE;
  SELECT * INTO s FROM public.sessions WHERE academy_id = p_academy AND id = p_session FOR UPDATE;
  PERFORM private.check_revision(s.revision, p_expected_revision);
  IF s.status NOT IN ('OPEN','CLOSED') THEN PERFORM private.fail('INVALID_STATE'); END IF;
  PERFORM 1 FROM public.player_packages k WHERE k.academy_id = p_academy AND k.id IN (SELECT b.package_id FROM public.bookings b
    WHERE b.academy_id = p_academy AND b.session_id = p_session AND b.status IN ('PENDING','CONFIRMED')) ORDER BY k.id FOR UPDATE;
  FOR v_booking IN SELECT b.id FROM public.bookings b WHERE b.academy_id = p_academy AND b.session_id = p_session
      AND b.status IN ('PENDING','CONFIRMED') ORDER BY b.id FOR UPDATE LOOP
    PERFORM private.terminate_booking(ctx, v_booking, 'CANCELLED', v_reason, 'cancel:' || v_booking);
    v_count := v_count + 1;
  END LOOP;
  UPDATE public.sessions SET status = 'CANCELLED', revision = revision + 1, updated_by = auth.uid() WHERE id = p_session RETURNING * INTO s;
  PERFORM private.audit(ctx, 'audit', 'session.cancelled', 'session', p_session, v_reason, jsonb_build_object('bookings_cancelled', v_count));
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CANCELLED', 'session_id', p_session, 'revision', s.revision,
    'bookings_cancelled', v_count));
END;
$$;

-- Evaluations: assigned coach (or operational scope) after a completed session;
-- an observed absence cannot be evaluated.
CREATE FUNCTION private.validate_scores(VARIADIC p_scores integer[]) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(p_scores) x WHERE x IS NULL OR x NOT BETWEEN 1 AND 5) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
END;
$$;

CREATE FUNCTION public.record_evaluation(p_academy uuid, p_booking uuid, p_technical integer, p_tactical integer,
  p_physical integer, p_behavior integer, p_operation_key uuid, p_comment text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; b public.bookings; v_coach uuid; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'record_evaluation', p_operation_key, jsonb_build_object('booking', p_booking,
    'scores', jsonb_build_array(p_technical, p_tactical, p_physical, p_behavior), 'comment', p_comment));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  SELECT * INTO b FROM public.bookings WHERE academy_id = p_academy AND id = p_booking;
  IF NOT FOUND OR NOT (private.local_permission(p_academy, 'bookings.schedule') OR private.assigned_session(p_academy, b.session_id)) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  PERFORM private.require_permission(p_academy, 'evaluations.record');
  PERFORM private.validate_scores(p_technical, p_tactical, p_physical, p_behavior);
  IF length(p_comment) > 1000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  b := private.lock_booking(p_academy, p_booking);
  IF b.status <> 'COMPLETED' THEN PERFORM private.fail('INVALID_STATE'); END IF;
  IF EXISTS (SELECT 1 FROM public.booking_attendance a WHERE a.booking_id = b.id AND NOT a.attended) THEN
    PERFORM private.fail('PLAYER_ABSENT');
  END IF;
  IF EXISTS (SELECT 1 FROM public.player_evaluations e WHERE e.booking_id = b.id) THEN PERFORM private.fail('ALREADY_EVALUATED'); END IF;
  SELECT coach_id INTO v_coach FROM public.sessions WHERE academy_id = p_academy AND id = b.session_id;
  INSERT INTO public.player_evaluations (academy_id, booking_id, session_id, coach_id, technical, tactical, physical, behavior,
    comment, evaluated_at, recorded_by)
  VALUES (p_academy, b.id, b.session_id, v_coach, p_technical, p_tactical, p_physical, p_behavior, coalesce(p_comment, ''),
    transaction_timestamp(), auth.uid()) RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'evaluation.recorded', 'evaluation', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'RECORDED', 'evaluation_id', v_id, 'revision', 1));
END;
$$;

CREATE FUNCTION public.correct_evaluation(p_academy uuid, p_evaluation uuid, p_technical integer, p_tactical integer,
  p_physical integer, p_behavior integer, p_expected_revision integer, p_reason text, p_operation_key uuid,
  p_comment text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; e public.player_evaluations; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'correct_evaluation', p_operation_key, jsonb_build_object('evaluation', p_evaluation,
    'scores', jsonb_build_array(p_technical, p_tactical, p_physical, p_behavior), 'comment', p_comment,
    'revision', p_expected_revision, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  SELECT * INTO e FROM public.player_evaluations WHERE academy_id = p_academy AND id = p_evaluation;
  IF NOT FOUND OR NOT (private.local_permission(p_academy, 'bookings.schedule') OR private.assigned_session(p_academy, e.session_id)) THEN
    PERFORM private.fail('NOT_FOUND', 'P0002');
  END IF;
  PERFORM private.require_permission(p_academy, 'evaluations.correct');
  PERFORM private.validate_scores(p_technical, p_tactical, p_physical, p_behavior);
  v_reason := private.reason(p_reason, true);
  IF length(p_comment) > 1000 THEN PERFORM private.fail('INVALID_INPUT', '22023'); END IF;
  SELECT * INTO e FROM public.player_evaluations WHERE id = p_evaluation FOR UPDATE;
  PERFORM private.check_revision(e.revision, p_expected_revision);
  UPDATE public.player_evaluations SET technical = p_technical, tactical = p_tactical, physical = p_physical,
    behavior = p_behavior, comment = coalesce(p_comment, ''), recorded_by = auth.uid(), revision = revision + 1
  WHERE id = p_evaluation RETURNING * INTO e;
  PERFORM private.audit(ctx, 'audit', 'evaluation.corrected', 'evaluation', p_evaluation, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CORRECTED', 'evaluation_id', p_evaluation, 'revision', e.revision));
END;
$$;

-- Tournaments stay private (published is always false); no registration model in V1.
CREATE FUNCTION public.create_tournament(p_academy uuid, p_name text, p_venue text, p_category text, p_starts_at timestamptz,
  p_capacity integer, p_operation_key uuid, p_description text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid;
BEGIN
  ctx := private.cmd_begin(p_academy, 'create_tournament', p_operation_key, jsonb_build_object('name', p_name, 'venue', p_venue,
    'category', p_category, 'starts_at', p_starts_at, 'capacity', p_capacity, 'description', p_description));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'tournaments.create');
  IF p_starts_at IS NULL OR NOT isfinite(p_starts_at) OR p_capacity IS NULL OR p_capacity NOT BETWEEN 2 AND 10000
     OR length(p_description) > 1000 THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  INSERT INTO public.tournaments (academy_id, created_by, updated_by, name, venue, category, description, starts_at, capacity, status)
  VALUES (p_academy, auth.uid(), auth.uid(), private.require_text(p_name, 150), private.require_text(p_venue, 200),
    private.require_text(p_category, 100), coalesce(p_description, ''), p_starts_at, p_capacity, 'OPEN') RETURNING id INTO v_id;
  PERFORM private.audit(ctx, 'audit', 'tournament.created', 'tournament', v_id);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'CREATED', 'tournament_id', v_id));
END;
$$;

CREATE FUNCTION public.update_tournament(p_academy uuid, p_tournament uuid, p_operation_key uuid, p_name text DEFAULT NULL,
  p_venue text DEFAULT NULL, p_category text DEFAULT NULL, p_starts_at timestamptz DEFAULT NULL, p_capacity integer DEFAULT NULL,
  p_description text DEFAULT NULL, p_status text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb;
BEGIN
  ctx := private.cmd_begin(p_academy, 'update_tournament', p_operation_key, jsonb_build_object('tournament', p_tournament,
    'name', p_name, 'venue', p_venue, 'category', p_category, 'starts_at', p_starts_at, 'capacity', p_capacity,
    'description', p_description, 'status', p_status));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'tournaments.update');
  IF (p_starts_at IS NOT NULL AND NOT isfinite(p_starts_at)) OR (p_capacity IS NOT NULL AND p_capacity NOT BETWEEN 2 AND 10000)
     OR length(p_description) > 1000 OR (p_status IS NOT NULL AND p_status NOT IN ('OPEN','CLOSED')) THEN
    PERFORM private.fail('INVALID_INPUT', '22023');
  END IF;
  UPDATE public.tournaments SET updated_by = auth.uid(),
    name = CASE WHEN p_name IS NULL THEN name ELSE private.require_text(p_name, 150) END,
    venue = CASE WHEN p_venue IS NULL THEN venue ELSE private.require_text(p_venue, 200) END,
    category = CASE WHEN p_category IS NULL THEN category ELSE private.require_text(p_category, 100) END,
    starts_at = coalesce(p_starts_at, starts_at), capacity = coalesce(p_capacity, capacity),
    description = coalesce(p_description, description), status = coalesce(p_status, status)
  WHERE academy_id = p_academy AND id = p_tournament AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'tournament.updated', 'tournament', p_tournament);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'UPDATED', 'tournament_id', p_tournament));
END;
$$;

CREATE FUNCTION public.archive_tournament(p_academy uuid, p_tournament uuid, p_reason text, p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE ctx jsonb; v_reason text;
BEGIN
  ctx := private.cmd_begin(p_academy, 'archive_tournament', p_operation_key, jsonb_build_object('tournament', p_tournament, 'reason', p_reason));
  IF ctx ? 'replay' THEN RETURN ctx -> 'replay'; END IF;
  PERFORM private.require_permission(p_academy, 'tournaments.archive');
  v_reason := private.reason(p_reason, true);
  UPDATE public.tournaments SET status = 'DELETED', deleted_at = transaction_timestamp(), deleted_by = auth.uid(), updated_by = auth.uid()
    WHERE academy_id = p_academy AND id = p_tournament AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND', 'P0002'); END IF;
  PERFORM private.audit(ctx, 'audit', 'tournament.archived', 'tournament', p_tournament, v_reason);
  RETURN private.cmd_finish(ctx, jsonb_build_object('outcome', 'ARCHIVED', 'tournament_id', p_tournament));
END;
$$;

DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('invite_member','revoke_invitation','set_membership_roles',
      'suspend_membership','reactivate_membership','transfer_ownership','create_academy','update_academy',
      'set_academy_status','create_plan','set_plan_active','create_subscription','transition_subscription',
      'create_stadium','update_stadium','archive_stadium','create_court','update_court','archive_court',
      'create_community','update_community','archive_community','create_community_course','update_community_course',
      'archive_community_course','create_coach','archive_coach','create_offer','publish_offer','retire_offer',
      'create_session','close_session','cancel_session','record_evaluation','correct_evaluation',
      'create_tournament','update_tournament','archive_tournament') LOOP
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
