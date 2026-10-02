-- Deferred constraint triggers execute after the SECURITY DEFINER RPC returns.
-- PostgREST commits as authenticated/service_role, which cannot read private
-- receipts directly. Keep the integrity check privileged, not the caller.
-- Its arguments come only from migration-owned triggers; search_path is fixed.
ALTER FUNCTION private.check_parent_scope() SECURITY DEFINER;
ALTER FUNCTION private.check_parent_scope() SET search_path = pg_catalog;
REVOKE ALL ON FUNCTION private.check_parent_scope() FROM PUBLIC, anon, authenticated, service_role;
