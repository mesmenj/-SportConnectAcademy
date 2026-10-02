-- Phase 6: periodic invocation of the five Edge workers with pg_cron + pg_net.
-- Installed INACTIVE. An operator enables it per environment after storing two
-- Vault secrets (see supabase/README.md). The worker secret is read from Vault at
-- dispatch time: it never appears in cron.job, job logs or any client grant.
-- Each worker call claims one item under a lease, so several calls per tick are
-- safe and set throughput. No retention (D28) is assumed: asset cleanup stays off
-- until asset_retention is explicitly set.
DO $$
BEGIN
 -- Absent from a plain PostgreSQL test cluster: the schedule then cannot be enabled.
 IF EXISTS(SELECT FROM pg_available_extensions WHERE name='pg_cron') THEN CREATE EXTENSION IF NOT EXISTS pg_cron; END IF;
 IF EXISTS(SELECT FROM pg_available_extensions WHERE name='pg_net') THEN CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions; END IF;
END;
$$;

-- Operations infrastructure lives in its own schema, outside the 41-table
-- application model of public/private. Closed to every client and service role.
CREATE SCHEMA ops;
REVOKE ALL ON SCHEMA ops FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE ops.worker_schedule(
 worker text PRIMARY KEY CHECK (worker IN ('provision-invitation','expand-email-outbox','deliver-email','schedule-notifications','cleanup-assets-and-content')),
 enabled boolean NOT NULL DEFAULT false,
 calls_per_tick smallint NOT NULL CHECK (calls_per_tick BETWEEN 1 AND 20),
 min_interval interval NOT NULL CHECK (min_interval BETWEEN interval '30 seconds' AND interval '1 day'),
 asset_retention interval CHECK (asset_retention IS NULL OR (worker='cleanup-assets-and-content' AND asset_retention>=interval '1 day')),
 last_dispatched_at timestamptz
);
INSERT INTO ops.worker_schedule(worker,calls_per_tick,min_interval) VALUES
 ('provision-invitation',5,'30 seconds'),('expand-email-outbox',5,'30 seconds'),('deliver-email',5,'30 seconds'),
 ('schedule-notifications',1,'1 minute'),('cleanup-assets-and-content',1,'1 hour');

CREATE TABLE ops.worker_dispatches(
 request_id bigint PRIMARY KEY,
 worker text NOT NULL REFERENCES ops.worker_schedule(worker),
 dispatched_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX worker_dispatches_worker_time ON ops.worker_dispatches(worker,dispatched_at DESC);
ALTER TABLE ops.worker_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.worker_dispatches ENABLE ROW LEVEL SECURITY;

-- Returns the validated functions base URL and worker secret, or fails.
CREATE FUNCTION ops.worker_scheduler_config(OUT base_url text,OUT worker_secret text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF to_regprocedure('cron.schedule(text,text,text)') IS NULL OR to_regproc('net.http_post') IS NULL
 OR to_regclass('vault.decrypted_secrets') IS NULL THEN PERFORM private.fail('SCHEDULER_UNAVAILABLE','55000'); END IF;
 EXECUTE 'SELECT max(decrypted_secret) FILTER (WHERE name=''sporta_functions_url''),
  max(decrypted_secret) FILTER (WHERE name=''sporta_worker_secret'') FROM vault.decrypted_secrets'
  INTO base_url,worker_secret;
 -- HTTPS, or the Docker-internal gateway of a local stack. No path, no trailing slash.
 IF base_url IS NULL OR base_url !~ '^(https://[a-z]{20}\.supabase\.co|http://(host\.docker\.internal|kong|supabase_kong_[a-z0-9_-]+)(:[0-9]{1,5})?)$'
 OR base_url='https://phjzyohsscwrgwvhgvfh.supabase.co'
 OR worker_secret IS NULL OR length(worker_secret)<32 THEN PERFORM private.fail('SCHEDULER_NOT_CONFIGURED','22023'); END IF;
END;
$$;

CREATE FUNCTION ops.dispatch_workers() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c record; w ops.worker_schedule; body jsonb; request bigint; n integer:=0;
BEGIN
 SELECT * INTO c FROM ops.worker_scheduler_config();
 DELETE FROM ops.worker_dispatches WHERE dispatched_at<clock_timestamp()-interval '1 day';
 -- SKIP LOCKED: an overlapping manual dispatch never doubles a worker's tick.
 FOR w IN SELECT * FROM ops.worker_schedule WHERE enabled
 AND (last_dispatched_at IS NULL OR last_dispatched_at<=clock_timestamp()-min_interval)
 ORDER BY worker FOR UPDATE SKIP LOCKED LOOP
  body:=CASE WHEN w.asset_retention IS NULL THEN '{}'::jsonb
   ELSE jsonb_build_object('asset_before',to_jsonb(clock_timestamp()-w.asset_retention)) END;
  FOR i IN 1..w.calls_per_tick LOOP
   EXECUTE 'SELECT net.http_post(url:=$1,body:=$2,headers:=$3,timeout_milliseconds:=25000)' INTO request
    USING c.base_url||'/functions/v1/'||w.worker,body,
     jsonb_build_object('Content-Type','application/json','x-worker-secret',c.worker_secret);
   INSERT INTO ops.worker_dispatches(request_id,worker) VALUES(request,w.worker);
   n:=n+1;
  END LOOP;
  UPDATE ops.worker_schedule SET last_dispatched_at=clock_timestamp() WHERE worker=w.worker;
 END LOOP;
 RETURN n;
END;
$$;

-- Enables exactly the listed workers and (re)creates the single cron job.
CREATE FUNCTION ops.enable_worker_schedule(p_workers text[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE unknown text[];
BEGIN
 PERFORM ops.worker_scheduler_config();
 SELECT array_agg(x) INTO unknown FROM unnest(p_workers) x WHERE x NOT IN (SELECT worker FROM ops.worker_schedule);
 IF p_workers IS NULL OR cardinality(p_workers)=0 OR array_position(p_workers,NULL) IS NOT NULL OR unknown IS NOT NULL THEN PERFORM private.fail('INVALID_WORKERS','22023'); END IF;
 IF 'cleanup-assets-and-content'=ANY(p_workers) AND EXISTS(SELECT FROM ops.worker_schedule WHERE worker='cleanup-assets-and-content' AND asset_retention IS NULL) THEN
  PERFORM private.fail('RETENTION_REQUIRED','22023');
 END IF;
 UPDATE ops.worker_schedule SET enabled=(worker=ANY(p_workers));
 EXECUTE 'SELECT cron.schedule(''sporta-workers'',''30 seconds'',''SELECT ops.dispatch_workers()'')';
 RETURN jsonb_build_object('outcome','ENABLED','workers',(SELECT jsonb_agg(worker ORDER BY worker) FROM ops.worker_schedule WHERE enabled));
END;
$$;

CREATE FUNCTION ops.disable_worker_schedule() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 UPDATE ops.worker_schedule SET enabled=false;
 IF to_regclass('cron.job') IS NOT NULL THEN
  EXECUTE 'SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname=''sporta-workers''';
 END IF;
 RETURN jsonb_build_object('outcome','DISABLED');
END;
$$;

-- Operator view of the last hour: a 401 means the Vault and Edge secrets differ.
CREATE FUNCTION ops.worker_schedule_status() RETURNS TABLE(worker text,enabled boolean,last_dispatched_at timestamptz,
 dispatched bigint,succeeded bigint,failed bigint,pending bigint,last_failure text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF to_regclass('net._http_response') IS NULL THEN
  RETURN QUERY SELECT s.worker,s.enabled,s.last_dispatched_at,0::bigint,0::bigint,0::bigint,0::bigint,NULL::text
   FROM ops.worker_schedule s ORDER BY s.worker;
  RETURN;
 END IF;
 RETURN QUERY EXECUTE $q$
  SELECT s.worker,s.enabled,s.last_dispatched_at,count(d.request_id),
   count(*) FILTER (WHERE r.status_code BETWEEN 200 AND 299),
   count(*) FILTER (WHERE r.id IS NOT NULL AND (r.status_code IS NULL OR r.status_code NOT BETWEEN 200 AND 299)),
   count(*) FILTER (WHERE d.request_id IS NOT NULL AND r.id IS NULL),
   (array_agg(coalesce(r.status_code::text,'')||' '||coalesce(left(r.content,120),r.error_msg,'')
    ORDER BY d.dispatched_at DESC) FILTER (WHERE r.id IS NOT NULL AND (r.status_code IS NULL OR r.status_code NOT BETWEEN 200 AND 299)))[1]
  FROM ops.worker_schedule s
  LEFT JOIN ops.worker_dispatches d ON d.worker=s.worker AND d.dispatched_at>clock_timestamp()-interval '1 hour'
  LEFT JOIN net._http_response r ON r.id=d.request_id
  GROUP BY s.worker,s.enabled,s.last_dispatched_at ORDER BY s.worker $q$;
END;
$$;

REVOKE ALL ON TABLE ops.worker_schedule,ops.worker_dispatches FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION ops.worker_scheduler_config(),ops.dispatch_workers(),ops.enable_worker_schedule(text[]),
 ops.disable_worker_schedule(),ops.worker_schedule_status() FROM PUBLIC,anon,authenticated,service_role;
-- pg_net's own tables (whose queue briefly holds the worker secret header) are
-- granted to PUBLIC by their owner, supabase_admin; this migration cannot revoke
-- that. Client roles are NOLOGIN and reach the database only through the API,
-- which must expose the public schema alone: verified by the local scheduler test
-- and enforced by scripts/staging-preflight.mjs.
