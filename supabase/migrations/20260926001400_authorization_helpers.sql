-- Phase 3B. Only the verified Auth subject identifies the actor. No role/academy
-- claim, user_metadata, supplied user UUID or service key is an authorization.
-- Definers are owned by the migration role, never anon/authenticated. No writes.
CREATE FUNCTION private.active_actor() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_profiles p
    WHERE p.id = (SELECT auth.uid()) AND p.status = 'ACTIVE');
$$;

CREATE FUNCTION private.has_local_role(p_academy uuid, p_role text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.active_actor() AND EXISTS (
    SELECT 1 FROM public.academy_memberships m
    JOIN public.academies a ON a.id = m.academy_id
    JOIN private.academy_membership_roles r ON r.academy_id = m.academy_id AND r.membership_id = m.id
    WHERE m.academy_id = p_academy AND m.user_id = (SELECT auth.uid())
      AND m.status = 'ACTIVE' AND a.status = 'ACTIVE' AND a.deleted_at IS NULL
      AND r.revoked_at IS NULL AND r.role_code = p_role);
$$;

CREATE FUNCTION private.local_permission(p_academy uuid, p_permission text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.active_actor() AND EXISTS (
    SELECT 1 FROM public.academy_memberships m
    JOIN public.academies a ON a.id = m.academy_id
    JOIN private.academy_membership_roles r ON r.academy_id = m.academy_id AND r.membership_id = m.id
    JOIN private.academy_role_permissions rp ON rp.role_code = r.role_code
    WHERE m.academy_id = p_academy AND m.user_id = (SELECT auth.uid())
      AND m.status = 'ACTIVE' AND a.status = 'ACTIVE' AND a.deleted_at IS NULL
      AND r.revoked_at IS NULL AND rp.permission_code = p_permission);
$$;

CREATE FUNCTION private.platform_permission(p_permission text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.active_actor() AND EXISTS (
    SELECT 1 FROM private.platform_user_roles r
    JOIN private.platform_role_permissions rp ON rp.role_code = r.role_code
    WHERE r.user_id = (SELECT auth.uid()) AND r.revoked_at IS NULL
      AND rp.permission_code = p_permission);
$$;

CREATE FUNCTION private.linked_player(p_academy uuid, p_player uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM public.player_links l
    WHERE l.academy_id = p_academy AND l.player_id = p_player
      AND l.user_id = (SELECT auth.uid()) AND l.revoked_at IS NULL
      AND ((l.relationship = 'SELF' AND private.has_local_role(p_academy, 'STUDENT'))
        OR (l.relationship = 'GUARDIAN' AND private.has_local_role(p_academy, 'PARENT'))));
$$;

CREATE FUNCTION private.own_coach(p_academy uuid, p_coach uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.has_local_role(p_academy, 'COACH') AND EXISTS (
    SELECT 1 FROM public.coaches c
    JOIN public.academy_memberships m ON m.academy_id = c.academy_id AND m.id = c.membership_id
    WHERE c.academy_id = p_academy AND c.id = p_coach AND c.active AND c.deleted_at IS NULL
      AND m.user_id = (SELECT auth.uid()) AND m.status = 'ACTIVE');
$$;

CREATE FUNCTION private.assigned_session(p_academy uuid, p_session uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy
    AND s.id = p_session AND private.own_coach(p_academy, s.coach_id));
$$;

CREATE FUNCTION private.can_read_player(p_academy uuid, p_player uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.local_permission(p_academy, 'players.read') AND (
    private.local_permission(p_academy, 'bookings.schedule')
    OR private.linked_player(p_academy, p_player)
    OR EXISTS (SELECT 1 FROM public.bookings b WHERE b.academy_id = p_academy
      AND b.player_id = p_player AND private.assigned_session(p_academy, b.session_id)));
$$;

CREATE FUNCTION private.can_read_booking(p_academy uuid, p_booking uuid, p_action text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT p_action IN ('bookings.read','attendance.read','evaluations.read')
    AND private.local_permission(p_academy, p_action) AND EXISTS (
      SELECT 1 FROM public.bookings b WHERE b.academy_id = p_academy AND b.id = p_booking
        AND (private.local_permission(p_academy, 'bookings.schedule')
          OR private.linked_player(p_academy, b.player_id)
          OR private.assigned_session(p_academy, b.session_id)));
$$;

CREATE FUNCTION private.can_read_session(p_academy uuid, p_session uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.local_permission(p_academy, 'sessions.read') AND (
    private.local_permission(p_academy, 'service_offers.read')
    OR private.assigned_session(p_academy, p_session));
$$;

CREATE FUNCTION private.can_read_coach(p_academy uuid, p_coach uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.local_permission(p_academy, 'coaches.read') AND EXISTS (
    SELECT 1 FROM public.coaches c WHERE c.academy_id = p_academy AND c.id = p_coach
      AND (private.local_permission(p_academy, 'coaches.create')
        OR (c.active AND c.deleted_at IS NULL
          AND private.local_permission(p_academy, 'service_offers.read'))
        OR private.own_coach(p_academy, p_coach)));
$$;

CREATE FUNCTION private.can_read_offer(p_academy uuid, p_offer uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM public.service_offers o WHERE o.academy_id = p_academy AND o.id = p_offer
    AND ((private.local_permission(p_academy, 'service_offers.read') AND (
      o.status = 'PUBLISHED' OR private.local_permission(p_academy, 'service_offers.create')
      OR EXISTS (SELECT 1 FROM public.player_packages p WHERE p.academy_id = p_academy
        AND p.service_offer_id = p_offer AND private.linked_player(p_academy, p.player_id))))
      OR EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy
        AND s.service_offer_id = p_offer AND private.assigned_session(p_academy, s.id))));
$$;

CREATE FUNCTION private.can_read_membership(p_academy uuid, p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.local_permission(p_academy, 'memberships.read') AND (
    p_user = (SELECT auth.uid()) OR private.local_permission(p_academy, 'memberships.set_roles'));
$$;

CREATE FUNCTION private.can_read_link(p_academy uuid, p_player uuid, p_user uuid, p_revoked_at timestamptz) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.local_permission(p_academy, 'player_links.read') AND (
    private.local_permission(p_academy, 'player_links.assign')
    OR (p_user = (SELECT auth.uid()) AND p_revoked_at IS NULL AND private.linked_player(p_academy, p_player)));
$$;

CREATE FUNCTION private.can_read_finance(p_academy uuid, p_player uuid, p_action text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT p_action IN ('payments.read','invoices.read')
    AND private.local_permission(p_academy, p_action) AND (
      private.local_permission(p_academy, 'payments.record')
      OR private.linked_player(p_academy, p_player));
$$;

CREATE FUNCTION private.can_read_plan(p_plan uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT private.platform_permission('plans.read') OR EXISTS (
    SELECT 1 FROM public.academy_subscriptions s WHERE s.plan_id = p_plan
      AND private.local_permission(s.academy_id, 'subscriptions.read'));
$$;

CREATE FUNCTION private.can_read_resource(p_academy uuid, p_kind text, p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT CASE p_kind
    WHEN 'stadiums' THEN EXISTS (SELECT 1 FROM public.stadiums r WHERE r.id = p_id AND r.academy_id = p_academy
      AND ((private.local_permission(p_academy, 'stadiums.read') AND ((r.active AND r.deleted_at IS NULL) OR private.local_permission(p_academy, 'stadiums.create')))
        OR EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy AND s.stadium_id = p_id AND private.assigned_session(p_academy, s.id))))
    WHEN 'courts' THEN EXISTS (SELECT 1 FROM public.courts r WHERE r.id = p_id AND r.academy_id = p_academy
      AND ((private.local_permission(p_academy, 'courts.read') AND ((r.active AND r.deleted_at IS NULL) OR private.local_permission(p_academy, 'courts.create')))
        OR EXISTS (SELECT 1 FROM public.sessions s WHERE s.academy_id = p_academy AND s.court_id = p_id AND private.assigned_session(p_academy, s.id))))
    WHEN 'communities' THEN EXISTS (SELECT 1 FROM public.communities r WHERE r.id = p_id AND r.academy_id = p_academy
      AND private.local_permission(p_academy, 'communities.read')
      AND ((r.active AND r.deleted_at IS NULL) OR private.local_permission(p_academy, 'communities.create')))
    WHEN 'community_courses' THEN EXISTS (SELECT 1 FROM public.community_courses r WHERE r.id = p_id AND r.academy_id = p_academy
      AND private.local_permission(p_academy, 'community_courses.read')
      AND ((r.active AND r.deleted_at IS NULL) OR private.local_permission(p_academy, 'community_courses.create')))
    ELSE false END;
$$;

-- No direct client schema access. Only policy entry points receive EXECUTE in
-- the next migration; their pre-bound OIDs do not require client schema USAGE.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
