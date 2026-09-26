-- Phase 3B read-only API: fixed fields, live authorization, no arbitrary SQL.
CREATE FUNCTION private.require_active_actor() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  IF NOT private.active_actor() THEN
    RAISE EXCEPTION 'Authentication required or account unavailable' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE FUNCTION private.validate_page(p_limit integer, p_at timestamptz, p_id uuid, p_max integer DEFAULT 100) RETURNS void
LANGUAGE plpgsql STABLE SET search_path = pg_catalog AS $$
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > p_max OR ((p_at IS NULL) <> (p_id IS NULL)) THEN
    RAISE EXCEPTION 'Invalid page size or cursor' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE FUNCTION private.validate_window(p_from timestamptz, p_until timestamptz) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog AS $$
BEGIN
  IF p_from IS NULL OR p_until IS NULL OR NOT isfinite(p_from) OR NOT isfinite(p_until)
     OR p_until <= p_from OR p_until - p_from > interval '366 days' THEN
    RAISE EXCEPTION 'A finite window of at most 366 days is required' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE FUNCTION private.read_page(p_rows jsonb, p_limit integer, p_time_key text DEFAULT 'created_at') RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
  SELECT jsonb_build_object('items', coalesce((SELECT jsonb_agg(value ORDER BY ord)
    FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY AS x(value,ord)
    WHERE ord <= p_limit), '[]'::jsonb),
    'next_cursor', CASE WHEN jsonb_array_length(coalesce(p_rows,'[]'::jsonb)) > p_limit
      THEN jsonb_build_object('at', p_rows -> (p_limit-1) -> p_time_key, 'id', p_rows -> (p_limit-1) -> 'id')
      ELSE NULL END);
$$;

CREATE FUNCTION public.get_access_context(p_academy uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  RETURN jsonb_build_object(
    'user_id', auth.uid(),
    'platform_roles', coalesce((SELECT jsonb_agg(r.role_code ORDER BY r.role_code)
      FROM private.platform_user_roles r WHERE r.user_id = auth.uid() AND r.revoked_at IS NULL), '[]'::jsonb),
    'platform_permissions', coalesce((SELECT jsonb_agg(code ORDER BY code) FROM (
      SELECT DISTINCT rp.permission_code AS code FROM private.platform_user_roles r
      JOIN private.platform_role_permissions rp ON rp.role_code = r.role_code
      WHERE r.user_id = auth.uid() AND r.revoked_at IS NULL) q), '[]'::jsonb),
    'academy_id', CASE WHEN private.local_permission(p_academy, 'academy.read') THEN p_academy END,
    'academy_roles', coalesce((SELECT jsonb_agg(r.code ORDER BY r.code) FROM public.academy_roles r
      WHERE private.has_local_role(p_academy, r.code)), '[]'::jsonb),
    'academy_permissions', coalesce((SELECT jsonb_agg(p.code ORDER BY p.code) FROM public.permissions p
      WHERE private.local_permission(p_academy, p.code)), '[]'::jsonb));
END;
$$;

CREATE FUNCTION public.list_my_academies(p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', a.id, 'created_at', a.created_at, 'name', a.name,
      'city', a.city, 'country', a.country, 'timezone', a.timezone, 'language', a.default_language,
      'logo_asset_id', a.logo_asset_id, 'membership_id', m.id) AS row_data
    FROM public.academies a JOIN public.academy_memberships m ON m.academy_id = a.id
    WHERE m.user_id = auth.uid() AND m.status = 'ACTIVE'
      AND private.local_permission(a.id, 'academy.read') AND (p_before_at IS NULL OR (a.created_at, a.id) < (p_before_at, p_before_id))
    ORDER BY a.created_at DESC, a.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_platform_academies(p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', a.id, 'created_at', a.created_at, 'name', a.name,
      'city', a.city, 'country', a.country, 'status', a.status,
      'active_member_count', (SELECT count(*) FROM public.academy_memberships m WHERE m.academy_id = a.id AND m.status = 'ACTIVE')) AS row_data
    FROM public.academies a WHERE private.platform_permission('academies.read_metadata') AND (p_before_at IS NULL OR (a.created_at, a.id) < (p_before_at, p_before_id))
    ORDER BY a.created_at DESC, a.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_memberships(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object('id', m.id, 'created_at', m.created_at,
      'display_name', p.display_name, 'status', m.status,
      'user_id', CASE WHEN private.can_read_membership(p_academy, m.user_id) THEN m.user_id END,
      'roles', coalesce((SELECT jsonb_agg(r.role_code ORDER BY r.role_code) FROM private.academy_membership_roles r
        WHERE r.academy_id = p_academy AND r.membership_id = m.id AND r.revoked_at IS NULL), '[]'::jsonb))) AS row_data
    FROM public.academy_memberships m JOIN public.user_profiles p ON p.id = m.user_id
    WHERE m.academy_id = p_academy AND private.local_permission(p_academy, 'memberships.read')
      AND (private.can_read_membership(p_academy, m.user_id) OR (
        private.local_permission(p_academy, 'bookings.schedule') AND m.status = 'ACTIVE' AND p.status = 'ACTIVE'))
      AND (p_before_at IS NULL OR (m.created_at, m.id) < (p_before_at, p_before_id)) ORDER BY m.created_at DESC, m.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_invitations(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', i.id, 'created_at', i.created_at, 'email', i.email,
      'requested_roles', i.requested_role_codes, 'status', i.status, 'expires_at', i.expires_at) AS row_data
    FROM private.academy_invitations i WHERE i.academy_id = p_academy
      AND private.local_permission(p_academy, 'memberships.invite') AND (p_before_at IS NULL OR (i.created_at, i.id) < (p_before_at, p_before_id))
    ORDER BY i.created_at DESC, i.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_players(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', p.id, 'created_at', p.created_at, 'first_name', p.first_name,
      'last_name', p.last_name, 'status', p.status) AS row_data
    FROM public.players p WHERE p.academy_id = p_academy AND p.deleted_at IS NULL
      AND private.can_read_player(p_academy, p.id) AND (p_before_at IS NULL OR (p.created_at, p.id) < (p_before_at, p_before_id))
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.get_player_profile(p_academy uuid, p_player uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  SELECT jsonb_build_object('id', p.id, 'academy_id', p.academy_id, 'first_name', p.first_name,
      'last_name', p.last_name, 'status', p.status,
      'age', CASE WHEN p.birth_date IS NOT NULL THEN extract(year FROM age(current_date, p.birth_date))::integer ELSE p.reported_age END)
    || CASE WHEN private.local_permission(p_academy, 'players.archive') OR private.linked_player(p_academy, p.id)
      THEN jsonb_build_object('birth_date', p.birth_date, 'reported_age', p.reported_age,
        'age_recorded_at', p.age_recorded_at, 'gender', p.gender, 'community_id', p.community_id)
      ELSE '{}'::jsonb END
    INTO result FROM public.players p WHERE p.academy_id = p_academy AND p.id = p_player
      AND private.can_read_player(p_academy, p.id);
  RETURN result;
END;
$$;

CREATE FUNCTION public.list_coaches(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', c.id, 'created_at', c.created_at,
      'display_name', p.display_name, 'specialties', c.specialties, 'active', c.active) AS row_data
    FROM public.coaches c JOIN public.academy_memberships m ON m.academy_id = c.academy_id AND m.id = c.membership_id
    JOIN public.user_profiles p ON p.id = m.user_id
    WHERE c.academy_id = p_academy AND private.can_read_coach(p_academy, c.id) AND (p_before_at IS NULL OR (c.created_at, c.id) < (p_before_at, p_before_id))
    ORDER BY c.created_at DESC, c.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_service_offers(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', o.id, 'created_at', o.created_at, 'offer_key', o.offer_key,
      'version', o.version, 'name', o.name, 'activity', o.activity, 'session_type', o.session_type,
      'min_age', o.min_age, 'max_age', o.max_age, 'session_count', o.session_count,
      'duration_minutes', o.duration_minutes, 'price_basis', o.price_basis, 'status', o.status)
      || CASE WHEN private.local_permission(p_academy, 'service_offers.read')
        THEN jsonb_build_object('price', o.price::text, 'currency', o.currency) ELSE '{}'::jsonb END AS row_data
    FROM public.service_offers o WHERE o.academy_id = p_academy AND private.can_read_offer(p_academy, o.id)
      AND (p_before_at IS NULL OR (o.created_at, o.id) < (p_before_at, p_before_id)) ORDER BY o.created_at DESC, o.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_sessions(p_academy uuid, p_from timestamptz, p_until timestamptz, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  PERFORM private.validate_window(p_from, p_until);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
      'service_offer_id', s.service_offer_id, 'coach_id', s.coach_id, 'stadium_id', s.stadium_id,
      'court_id', s.court_id, 'capacity', s.capacity, 'occupied_places', s.occupied_places,
      'status', s.status, 'revision', s.revision) AS row_data
    FROM public.sessions s WHERE s.academy_id = p_academy AND s.starts_at >= p_from AND s.starts_at < p_until
      AND private.can_read_session(p_academy, s.id) AND (p_before_at IS NULL OR (s.starts_at, s.id) < (p_before_at, p_before_id))
    ORDER BY s.starts_at DESC, s.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'starts_at');
END;
$$;

CREATE FUNCTION public.list_bookings(p_academy uuid, p_from timestamptz, p_until timestamptz, p_player uuid DEFAULT NULL, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  PERFORM private.validate_window(p_from, p_until);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', b.id, 'session_id', b.session_id, 'player_id', b.player_id,
      'package_id', b.package_id, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'status', b.status,
      'revision', b.revision, 'client_can_reject', b.client_can_reject, 'deleted_at', b.deleted_at,
      'attended', CASE WHEN private.can_read_booking(p_academy, b.id, 'attendance.read') THEN a.attended END) AS row_data
    FROM public.bookings b JOIN public.sessions s ON s.academy_id = b.academy_id AND s.id = b.session_id
    LEFT JOIN public.booking_attendance a ON a.academy_id = b.academy_id AND a.booking_id = b.id
    WHERE b.academy_id = p_academy AND (p_player IS NULL OR b.player_id = p_player)
      AND s.starts_at >= p_from AND s.starts_at < p_until
      AND private.can_read_booking(p_academy, b.id, 'bookings.read')
      AND (p_before_at IS NULL OR (s.starts_at, b.id) < (p_before_at, p_before_id))
    ORDER BY s.starts_at DESC, b.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'starts_at');
END;
$$;

CREATE FUNCTION public.list_player_packages(p_academy uuid, p_player uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', p.id, 'created_at', p.created_at, 'player_id', p.player_id,
      'service_offer_id', p.service_offer_id, 'status', p.status,
      'availability_valid', p.remaining_sessions >= h.held,
      'available_sessions', CASE WHEN p.remaining_sessions >= h.held THEN p.remaining_sessions - h.held END)
      || CASE WHEN private.local_permission(p_academy, 'course_ledger.read') THEN
        jsonb_build_object('purchased_sessions', p.purchased_sessions, 'remaining_sessions', p.remaining_sessions, 'confirmed_unconsumed_bookings', h.held)
        ELSE '{}'::jsonb END
      || CASE WHEN private.local_permission(p_academy, 'packages.purchase') THEN
        jsonb_build_object('total_price', p.total_price::text, 'currency', p.currency, 'payment_state', p.payment_state, 'terms_snapshot', p.terms_snapshot)
        ELSE '{}'::jsonb END AS row_data
    FROM public.player_packages p
    CROSS JOIN LATERAL (SELECT count(*) AS held FROM public.bookings b
      WHERE b.academy_id = p.academy_id AND b.package_id = p.id AND b.status = 'CONFIRMED'
        AND coalesce((SELECT sum(l.delta) FROM private.course_ledger l WHERE l.academy_id = p.academy_id
          AND l.package_id = p.id AND l.booking_id = b.id
          AND l.reason IN ('SESSION_CONSUMED','BOOKING_CANCELLATION_CORRECTION','ATTENDANCE_CORRECTION')), 0) = 0) h
    WHERE p.academy_id = p_academy AND p.player_id = p_player
      AND private.local_permission(p_academy, 'packages.read') AND private.can_read_player(p_academy, p.player_id)
      AND (p_before_at IS NULL OR (p.created_at, p.id) < (p_before_at, p_before_id)) ORDER BY p.created_at DESC, p.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_course_ledger(p_academy uuid, p_package uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', l.id, 'created_at', l.created_at, 'occurred_at', l.occurred_at,
      'package_id', l.package_id, 'booking_id', l.booking_id, 'delta', l.delta, 'reason', l.reason) AS row_data
    FROM private.course_ledger l JOIN public.player_packages p ON p.academy_id = l.academy_id AND p.id = l.package_id
    WHERE l.academy_id = p_academy AND l.package_id = p_package
      AND private.local_permission(p_academy, 'course_ledger.read') AND private.can_read_player(p_academy, p.player_id)
      AND (p_before_at IS NULL OR (l.created_at, l.id) < (p_before_at, p_before_id)) ORDER BY l.created_at DESC, l.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_booking_events(p_academy uuid, p_booking uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', e.id, 'created_at', e.created_at, 'occurred_at', e.occurred_at,
      'event_type', e.event_type, 'before_status', e.before_status, 'after_status', e.after_status,
      'booking_revision', e.booking_revision) AS row_data
    FROM private.booking_events e WHERE e.academy_id = p_academy AND e.booking_id = p_booking
      AND private.can_read_booking(p_academy, p_booking, 'bookings.read') AND (p_before_at IS NULL OR (e.created_at, e.id) < (p_before_at, p_before_id))
    ORDER BY e.created_at DESC, e.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_payments(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', p.id, 'created_at', p.created_at, 'player_id', p.player_id,
      'package_id', p.package_id, 'amount', p.amount::text, 'currency', p.currency,
      'method', p.method, 'status', p.status, 'confirmed_at', p.confirmed_at) AS row_data
    FROM public.academy_payments p WHERE p.academy_id = p_academy
      AND private.can_read_finance(p_academy, p.player_id, 'payments.read') AND (p_before_at IS NULL OR (p.created_at, p.id) < (p_before_at, p_before_id))
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.list_invoices(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', i.id, 'created_at', i.created_at, 'issued_at', i.issued_at,
      'number', i.number, 'player_id', i.player_id, 'payment_id', i.payment_id,
      'amount', i.amount::text, 'currency', i.currency, 'status', i.status) AS row_data
    FROM public.academy_invoices i WHERE i.academy_id = p_academy
      AND private.can_read_finance(p_academy, i.player_id, 'invoices.read') AND (p_before_at IS NULL OR (i.issued_at, i.id) < (p_before_at, p_before_id))
    ORDER BY i.issued_at DESC, i.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'issued_at');
END;
$$;

CREATE FUNCTION public.get_invoice(p_academy uuid, p_invoice uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  SELECT jsonb_build_object('id', i.id, 'number', i.number, 'issued_at', i.issued_at,
      'player_id', i.player_id, 'payment_id', i.payment_id, 'amount', i.amount::text,
      'currency', i.currency, 'status', i.status, 'payment_method', i.payment_method,
      'issuer_snapshot', i.issuer_snapshot, 'customer_snapshot', i.customer_snapshot,
      'player_name_snapshot', i.player_name_snapshot, 'description', i.description,
      'session_count', i.session_count, 'activity', i.activity)
    INTO result FROM public.academy_invoices i WHERE i.academy_id = p_academy AND i.id = p_invoice
      AND private.can_read_finance(p_academy, i.player_id, 'invoices.read');
  RETURN result;
END;
$$;

CREATE FUNCTION public.list_notification_metadata(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 50);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', d.id, 'created_at', d.created_at, 'status', d.status,
      'template', d.template, 'language', d.language, 'attempts', d.attempts,
      'accepted_at', d.accepted_at, 'delivered_at', d.delivered_at) AS row_data
    FROM private.notification_deliveries d WHERE d.scope = 'TENANT' AND d.academy_id = p_academy
      AND private.local_permission(p_academy, 'notifications.read_metadata') AND (p_before_at IS NULL OR (d.created_at, d.id) < (p_before_at, p_before_id))
    ORDER BY d.created_at DESC, d.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

CREATE FUNCTION public.read_audit(p_academy uuid, p_before_at timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private.require_active_actor();
  PERFORM private.validate_page(p_limit, p_before_at, p_before_id, 100);
  SELECT jsonb_agg(row_data) INTO result FROM (
    SELECT jsonb_build_object('id', a.id, 'created_at', a.created_at, 'occurred_at', a.occurred_at,
      'action', a.action, 'resource_type', a.resource_type, 'resource_id', a.resource_id) AS row_data
    FROM private.audit_log a WHERE (
      (p_academy IS NOT NULL AND a.scope = 'TENANT' AND a.academy_id = p_academy AND private.local_permission(p_academy, 'audit.read'))
      OR (p_academy IS NULL AND a.scope = 'PLATFORM' AND a.academy_id IS NULL AND private.platform_permission('audit.read')))
      AND (p_before_at IS NULL OR (a.created_at, a.id) < (p_before_at, p_before_id)) ORDER BY a.created_at DESC, a.id DESC
    LIMIT p_limit + 1
  ) page;
  RETURN private.read_page(result, p_limit, 'created_at');
END;
$$;

REVOKE ALL ON FUNCTION public.get_access_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_access_context(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_my_academies(timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_academies(timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_platform_academies(timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_platform_academies(timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_memberships(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_memberships(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_invitations(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_invitations(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_players(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_players(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.get_player_profile(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_player_profile(uuid,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_coaches(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_coaches(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_service_offers(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_service_offers(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_sessions(uuid,timestamptz,timestamptz,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_sessions(uuid,timestamptz,timestamptz,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_bookings(uuid,timestamptz,timestamptz,uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings(uuid,timestamptz,timestamptz,uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_player_packages(uuid,uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_player_packages(uuid,uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_course_ledger(uuid,uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_course_ledger(uuid,uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_booking_events(uuid,uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_booking_events(uuid,uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_payments(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_payments(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_invoices(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_invoices(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.get_invoice(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_invoice(uuid,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_notification_metadata(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_notification_metadata(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.read_audit(uuid,timestamptz,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.read_audit(uuid,timestamptz,uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION private.require_active_actor(), private.validate_page(integer,timestamptz,uuid,integer),
  private.validate_window(timestamptz,timestamptz), private.read_page(jsonb,integer,text) FROM PUBLIC, anon, authenticated;
-- No public raw views, no table-valued arbitrary selector, no realtime publication.
