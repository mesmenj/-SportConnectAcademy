-- 3B: only SELECT policies. Direct writes stay denied for every client role.
GRANT USAGE ON SCHEMA public TO authenticated;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;

GRANT SELECT (id, display_name, phone, preferred_language, status, created_at, updated_at)
  ON public.user_profiles TO authenticated;
CREATE POLICY profile_self_read ON public.user_profiles FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) AND (SELECT private.active_actor()));

GRANT SELECT (code, description) ON public.permissions, public.academy_roles TO authenticated;
CREATE POLICY permissions_read ON public.permissions FOR SELECT TO authenticated USING ((SELECT private.active_actor()));
CREATE POLICY academy_roles_read ON public.academy_roles FOR SELECT TO authenticated USING ((SELECT private.active_actor()));
GRANT SELECT (code, description) ON public.platform_roles TO authenticated;
CREATE POLICY platform_roles_read ON public.platform_roles FOR SELECT TO authenticated
  USING ((SELECT private.platform_permission('platform_roles.read')));

GRANT SELECT (id, name, city, country, address, timezone, default_language, status, logo_asset_id)
  ON public.academies TO authenticated;
CREATE POLICY academies_read ON public.academies FOR SELECT TO authenticated USING (
  private.local_permission(id, 'academy.read') OR (SELECT private.platform_permission('academies.read_metadata')));

GRANT SELECT (id, academy_id, user_id, status, joined_at) ON public.academy_memberships TO authenticated;
CREATE POLICY memberships_read ON public.academy_memberships FOR SELECT TO authenticated
  USING (private.can_read_membership(academy_id, user_id));

-- Shared safe subsets. Full DOB/contact/financial data requires a checked projection.
GRANT SELECT (id, academy_id, first_name, last_name, status, created_at, updated_at, deleted_at)
  ON public.players TO authenticated;
CREATE POLICY players_read ON public.players FOR SELECT TO authenticated USING (private.can_read_player(academy_id, id));
GRANT SELECT (id, academy_id, player_id, user_id, relationship, is_primary, is_financial_contact, revoked_at)
  ON public.player_links TO authenticated;
CREATE POLICY player_links_read ON public.player_links FOR SELECT TO authenticated
  USING (private.can_read_link(academy_id, player_id, user_id, revoked_at));

GRANT SELECT (id, academy_id, active, specialties, created_at) ON public.coaches TO authenticated;
CREATE POLICY coaches_read ON public.coaches FOR SELECT TO authenticated USING (private.can_read_coach(academy_id, id));
GRANT SELECT (id, academy_id, name, address, active) ON public.stadiums TO authenticated;
CREATE POLICY stadiums_read ON public.stadiums FOR SELECT TO authenticated USING (private.can_read_resource(academy_id, 'stadiums', id));
GRANT SELECT (id, academy_id, stadium_id, number, label, active) ON public.courts TO authenticated;
CREATE POLICY courts_read ON public.courts FOR SELECT TO authenticated USING (private.can_read_resource(academy_id, 'courts', id));
GRANT SELECT (id, academy_id, name, description, active) ON public.communities TO authenticated;
CREATE POLICY communities_read ON public.communities FOR SELECT TO authenticated USING (private.can_read_resource(academy_id, 'communities', id));
GRANT SELECT (id, academy_id, community_id, name, description, active) ON public.community_courses TO authenticated;
CREATE POLICY community_courses_read ON public.community_courses FOR SELECT TO authenticated USING (private.can_read_resource(academy_id, 'community_courses', id));

GRANT SELECT (id, academy_id, offer_key, version, name, activity, session_type, min_age, max_age,
  session_count, price_basis, duration_minutes, status) ON public.service_offers TO authenticated;
CREATE POLICY offers_read ON public.service_offers FOR SELECT TO authenticated USING (private.can_read_offer(academy_id, id));
GRANT SELECT (id, academy_id, player_id, service_offer_id, status) ON public.player_packages TO authenticated;
CREATE POLICY packages_read ON public.player_packages FOR SELECT TO authenticated USING (
  private.local_permission(academy_id, 'packages.read') AND private.can_read_player(academy_id, player_id));

GRANT SELECT (id, academy_id, service_offer_id, coach_id, stadium_id, court_id, starts_at, ends_at,
  capacity, occupied_places, status, revision, created_at) ON public.sessions TO authenticated;
CREATE POLICY sessions_read ON public.sessions FOR SELECT TO authenticated USING (private.can_read_session(academy_id, id));
GRANT SELECT (id, academy_id, session_id, player_id, package_id, service_offer_id, status,
  client_can_reject, completion_source, revision, created_at, updated_at, deleted_at) ON public.bookings TO authenticated;
CREATE POLICY bookings_read ON public.bookings FOR SELECT TO authenticated USING (private.can_read_booking(academy_id, id, 'bookings.read'));
GRANT SELECT (booking_id, academy_id, attended, recorded_at, revision) ON public.booking_attendance TO authenticated;
CREATE POLICY attendance_read ON public.booking_attendance FOR SELECT TO authenticated USING (private.can_read_booking(academy_id, booking_id, 'attendance.read'));
GRANT SELECT (id, academy_id, booking_id, session_id, coach_id, technical, tactical, physical,
  behavior, comment, evaluated_at, revision) ON public.player_evaluations TO authenticated;
CREATE POLICY evaluations_read ON public.player_evaluations FOR SELECT TO authenticated USING (private.can_read_booking(academy_id, booking_id, 'evaluations.read'));

GRANT SELECT (id, academy_id, player_id, package_id, amount, currency, method, status, confirmed_at, created_at)
  ON public.academy_payments TO authenticated;
CREATE POLICY payments_read ON public.academy_payments FOR SELECT TO authenticated USING (private.can_read_finance(academy_id, player_id, 'payments.read'));
GRANT SELECT (id, academy_id, player_id, payment_id, number, issued_at, amount, currency, status, payment_method)
  ON public.academy_invoices TO authenticated;
CREATE POLICY invoices_read ON public.academy_invoices FOR SELECT TO authenticated USING (private.can_read_finance(academy_id, player_id, 'invoices.read'));

GRANT SELECT (id, academy_id, name, venue, category, description, starts_at, capacity, status, cover_asset_id)
  ON public.tournaments TO authenticated;
CREATE POLICY tournaments_read ON public.tournaments FOR SELECT TO authenticated USING (
  private.local_permission(academy_id, 'tournaments.read') AND (
    private.local_permission(academy_id, 'tournaments.create') OR (deleted_at IS NULL AND status <> 'DELETED')));
GRANT SELECT (id, code, version, name, active, description) ON public.platform_plans TO authenticated;
CREATE POLICY plans_read ON public.platform_plans FOR SELECT TO authenticated USING (private.can_read_plan(id));
GRANT SELECT (id, academy_id, plan_id, status, starts_at, ends_at, trial_ends_at, revision)
  ON public.academy_subscriptions TO authenticated;
CREATE POLICY subscriptions_read ON public.academy_subscriptions FOR SELECT TO authenticated USING (
  private.local_permission(academy_id, 'subscriptions.read') OR (SELECT private.platform_permission('subscriptions.read')));

-- Exact policy dependencies; private schema itself remains inaccessible.
GRANT EXECUTE ON FUNCTION private.active_actor(), private.local_permission(uuid,text),
  private.platform_permission(text), private.can_read_player(uuid,uuid),
  private.can_read_booking(uuid,uuid,text), private.can_read_session(uuid,uuid),
  private.can_read_coach(uuid,uuid), private.can_read_offer(uuid,uuid),
  private.can_read_membership(uuid,uuid), private.can_read_link(uuid,uuid,uuid,timestamptz),
  private.can_read_finance(uuid,uuid,text), private.can_read_plan(uuid),
  private.can_read_resource(uuid,text,uuid) TO authenticated;
