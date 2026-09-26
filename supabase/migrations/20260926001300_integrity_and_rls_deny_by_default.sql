-- Structural integrity only: no booking business RPC, auth provisioning or policy.

CREATE FUNCTION private.protect_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  key text;
BEGIN
  FOREACH key IN ARRAY TG_ARGV LOOP
    IF (to_jsonb(NEW) -> key) IS DISTINCT FROM (to_jsonb(OLD) -> key) THEN
      RAISE EXCEPTION 'Immutable identity: %.%', TG_TABLE_NAME, key USING ERRCODE = '23514';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE FUNCTION private.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  NEW.updated_at := transaction_timestamp();
  RETURN NEW;
END;
$$;

CREATE FUNCTION private.reject_history_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  RAISE EXCEPTION 'Append-only history: %', TG_TABLE_NAME USING ERRCODE = '23514';
END;
$$;

-- Scope is immutable on both sides. The deferred trigger permits the receipt
-- to be inserted after its effects; its FK still requires existence at commit.
-- Parent identity/scope cannot change, so a later update cannot invalidate the
-- match. No HTTP, authorization or business decision is performed here.
CREATE FUNCTION private.check_parent_scope() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE
  child jsonb := to_jsonb(NEW);
  parent_scope text;
  parent_academy uuid;
  parent_id uuid := (child ->> TG_ARGV[2])::uuid;
  child_scope text := coalesce(child ->> 'scope', 'TENANT');
BEGIN
  IF parent_id IS NULL THEN RETURN NULL; END IF;
  EXECUTE format('SELECT scope, academy_id FROM %I.%I WHERE id = $1', TG_ARGV[0], TG_ARGV[1])
    INTO parent_scope, parent_academy USING parent_id;
  IF parent_scope IS NULL OR parent_scope <> child_scope
     OR parent_academy IS DISTINCT FROM (child ->> 'academy_id')::uuid THEN
    RAISE EXCEPTION 'Parent scope mismatch: %', TG_TABLE_NAME USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;

DO $$
DECLARE
  t record;
  keys text;
  has_updated boolean;
BEGIN
  FOR t IN
    SELECT c.table_schema, c.table_name
    FROM information_schema.tables c
    WHERE c.table_schema IN ('public','private') AND c.table_type = 'BASE TABLE'
  LOOP
    SELECT bool_or(column_name = 'updated_at')
      INTO has_updated
      FROM information_schema.columns
      WHERE table_schema = t.table_schema AND table_name = t.table_name;
    -- updated_at is managed separately, not immutable.
    SELECT string_agg(quote_literal(column_name), ', ' ORDER BY ordinal_position)
      INTO keys FROM information_schema.columns
      WHERE table_schema = t.table_schema AND table_name = t.table_name
        AND column_name IN ('id','academy_id','scope','operation_id','created_at','created_by',
          'booking_id','delivery_id','receipt_key');
    IF keys IS NOT NULL THEN
      EXECUTE format('CREATE TRIGGER protect_identity BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION private.protect_identity(%s)', t.table_schema, t.table_name, keys);
    END IF;
    IF has_updated THEN
      EXECUTE format('CREATE TRIGGER touch_updated_at BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at()', t.table_schema, t.table_name);
    END IF;
    -- No direct client access in phase 3A, including catalog tables.
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', t.table_schema, t.table_name);
    EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC, anon, authenticated', t.table_schema, t.table_name);
  END LOOP;
END;
$$;

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['course_ledger','booking_events','subscription_events','audit_log','command_receipts'] LOOP
    EXECUTE format('CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON private.%I FOR EACH ROW EXECUTE FUNCTION private.reject_history_mutation()', tbl);
    EXECUTE format('CREATE TRIGGER append_only_truncate BEFORE TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private.reject_history_mutation()', tbl);
  END LOOP;
END;
$$;

DO $$
DECLARE
  t record;
BEGIN
  FOR t IN SELECT table_schema, table_name FROM information_schema.columns
    WHERE table_schema IN ('public','private') AND column_name = 'operation_id'
  LOOP
    EXECUTE format('CREATE CONSTRAINT TRIGGER receipt_scope AFTER INSERT OR UPDATE ON %I.%I DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.check_parent_scope(''private'', ''command_receipts'', ''operation_id'')', t.table_schema, t.table_name);
  END LOOP;
END;
$$;

CREATE CONSTRAINT TRIGGER notification_event_scope
AFTER INSERT OR UPDATE ON private.notification_deliveries
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION private.check_parent_scope('private', 'notification_events', 'event_id');

CREATE CONSTRAINT TRIGGER notification_payload_scope
AFTER INSERT OR UPDATE ON private.notification_payloads
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION private.check_parent_scope('private', 'notification_deliveries', 'delivery_id');

CREATE CONSTRAINT TRIGGER notification_webhook_scope
AFTER INSERT OR UPDATE ON private.notification_webhook_receipts
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION private.check_parent_scope('private', 'notification_deliveries', 'delivery_id');

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
-- No CREATE POLICY in 3A. Owner/migration role retains DDL access.
