CREATE TEMP SEQUENCE assertion_number;
CREATE FUNCTION pg_temp.ok(condition boolean, label text) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
  RETURN 'ok ' || nextval('pg_temp.assertion_number') || ' - ' || label;
END;
$$;
CREATE FUNCTION pg_temp.rejects(statement text, expected text, label text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE actual text;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE;
  END;
  RETURN pg_temp.ok(actual = expected, label || ' [SQLSTATE ' || coalesce(actual, 'NO ERROR') || ']');
END;
$$;
CREATE FUNCTION pg_temp.id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;
$$;

