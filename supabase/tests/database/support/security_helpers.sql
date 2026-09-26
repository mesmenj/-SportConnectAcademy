-- Test-only role/JWT impersonation. Not a migration or application endpoint.
CREATE FUNCTION pg_temp.query_as(p_user integer, p_statement text, p_claims jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  result jsonb;
  old_sub text := current_setting('request.jwt.claim.sub', true);
  old_claims text := current_setting('request.jwt.claims', true);
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(pg_temp.id(p_user)::text,''), true);
  PERFORM set_config('request.jwt.claims', (p_claims || jsonb_build_object('sub',pg_temp.id(p_user)))::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    EXECUTE p_statement INTO result;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub', coalesce(old_sub,''), true);
    PERFORM set_config('request.jwt.claims', coalesce(old_claims,''), true);
    RAISE;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', coalesce(old_sub,''), true);
  PERFORM set_config('request.jwt.claims', coalesce(old_claims,''), true);
  RETURN result;
END;
$$;
CREATE FUNCTION pg_temp.visible(p_user integer, p_relation text, p_column text DEFAULT 'id') RETURNS integer
LANGUAGE plpgsql AS $$
BEGIN
  RETURN (pg_temp.query_as(p_user, format('SELECT to_jsonb(count(%I)) FROM %s',p_column,p_relation)) #>> '{}')::integer;
END;
$$;
CREATE FUNCTION pg_temp.items(p_user integer, p_call text) RETURNS jsonb
LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.query_as(p_user,'SELECT ' || p_call) -> 'items';
END;
$$;
