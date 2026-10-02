\set ON_ERROR_STOP on
\set QUIET 1
\pset format unaligned
\pset tuples_only on
BEGIN;
\ir support/helpers.sql
-- Plain PostgreSQL (test:database) has no pg_cron/pg_net/Vault; Supabase has all three.
SELECT to_regproc('net.http_post') IS NOT NULL AND to_regclass('vault.decrypted_secrets') IS NOT NULL
 AND to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL AS scheduler \gset
\if :scheduler
DELETE FROM vault.secrets WHERE name IN ('sporta_functions_url','sporta_worker_secret');
\endif

SELECT pg_temp.ok((SELECT array_agg(table_name::text ORDER BY table_name) FROM information_schema.tables WHERE table_schema='ops')='{worker_dispatches,worker_schedule}',
 'ops schema holds only the two scheduler tables, outside the 41 application tables');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM unnest(array['anon','authenticated','service_role']) r WHERE has_schema_privilege(r,'ops','USAGE')),
 'ops schema closed to client and service roles');
SELECT pg_temp.ok((SELECT count(*)=5 AND bool_and(NOT enabled) AND bool_and(asset_retention IS NULL) FROM ops.worker_schedule),
 'five workers installed, all disabled, no invented retention');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM unnest(array['anon','authenticated','service_role']) r, unnest(array['ops.worker_schedule','ops.worker_dispatches']) t
 WHERE has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE')), 'scheduler tables unavailable to client and service roles');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM unnest(array['anon','authenticated','service_role']) r, pg_proc p
 WHERE p.pronamespace='ops'::regnamespace AND p.proname IN ('worker_scheduler_config','dispatch_workers','enable_worker_schedule','disable_worker_schedule','worker_schedule_status')
 AND has_function_privilege(r,p.oid,'EXECUTE')), 'scheduler functions unavailable to client and service roles');
SELECT pg_temp.ok((SELECT count(*)=5 AND bool_and(prosecdef) AND bool_and(proconfig::text LIKE '%search_path=pg_catalog%') FROM pg_proc
 WHERE pronamespace='ops'::regnamespace AND proname IN ('worker_scheduler_config','dispatch_workers','enable_worker_schedule','disable_worker_schedule','worker_schedule_status')),
 'scheduler functions are definer functions with pinned search_path');
SELECT pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid='ops.worker_schedule'::regclass)
 AND (SELECT relrowsecurity FROM pg_class WHERE oid='ops.worker_dispatches'::regclass), 'RLS enabled on scheduler tables');
SELECT pg_temp.rejects($$UPDATE ops.worker_schedule SET asset_retention='30 days' WHERE worker='deliver-email'$$,'23514','retention only applies to cleanup');
SELECT pg_temp.rejects($$UPDATE ops.worker_schedule SET asset_retention='1 hour' WHERE worker='cleanup-assets-and-content'$$,'23514','retention shorter than one day refused');
SELECT pg_temp.rejects($$UPDATE ops.worker_schedule SET calls_per_tick=0 WHERE worker='deliver-email'$$,'23514','at least one call per tick');
SELECT pg_temp.rejects($$UPDATE ops.worker_schedule SET min_interval='5 seconds' WHERE worker='deliver-email'$$,'23514','interval of at least 30 seconds');
SELECT pg_temp.rejects($$INSERT INTO ops.worker_schedule(worker,calls_per_tick,min_interval) VALUES('send-emails',1,'1 minute')$$,'23514','legacy or unknown worker refused');
SELECT pg_temp.ok((SELECT count(*)=5 FROM ops.worker_schedule_status()), 'status lists every worker');
SELECT pg_temp.ok((ops.disable_worker_schedule())->>'outcome'='DISABLED', 'disable is always possible');

\if :scheduler
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation'])$$,'22023','enable refused without Vault configuration');
SELECT pg_temp.rejects($$SELECT ops.dispatch_workers()$$,'22023','dispatch refused without Vault configuration');
SELECT vault.create_secret('http://evil.example.test','sporta_functions_url') \g /dev/null
SELECT vault.create_secret(repeat('s',40),'sporta_worker_secret') \g /dev/null
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation'])$$,'22023','plain HTTP to a non-local host refused');
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='sporta_functions_url'),'https://abcdefghijklmnopqrst.supabase.co') \g /dev/null
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='sporta_worker_secret'),'short') \g /dev/null
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation'])$$,'22023','worker secret shorter than 32 characters refused');
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='sporta_worker_secret'),'test-worker-secret-'||repeat('x',32)) \g /dev/null
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation','send-emails'])$$,'22023','unknown worker in enable list refused');
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array[]::text[])$$,'22023','empty enable list refused');
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation',NULL])$$,'22023','null worker refused');
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['cleanup-assets-and-content'])$$,'22023','cleanup activation requires an explicit D28 retention');
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='sporta_functions_url'),'https://phjzyohsscwrgwvhgvfh.supabase.co') \g /dev/null
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation'])$$,'22023','protected production target refused');
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='sporta_functions_url'),'https://abcdefghijklmnopqrst.supabase.co') \g /dev/null
SELECT pg_temp.ok((ops.enable_worker_schedule(array['provision-invitation','expand-email-outbox']))->'workers'='["expand-email-outbox","provision-invitation"]'::jsonb,
 'enable activates exactly the listed workers');
SELECT pg_temp.ok((SELECT count(*)=1 AND bool_and(command='SELECT ops.dispatch_workers()') AND bool_and(schedule='30 seconds') FROM cron.job WHERE jobname='sporta-workers'),
 'one cron job, command carries no secret');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM cron.job WHERE command LIKE '%test-worker-secret%'), 'secret absent from every cron job');
SELECT pg_temp.ok(ops.dispatch_workers()=10, 'dispatch sends calls_per_tick requests to each enabled worker');
SELECT pg_temp.ok((SELECT count(*)=10 AND count(DISTINCT worker)=2 FROM ops.worker_dispatches), 'every request is recorded for monitoring');
SELECT pg_temp.ok((SELECT count(*)=10 AND bool_and(url LIKE 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/%')
 AND bool_and(headers->>'x-worker-secret'='test-worker-secret-'||repeat('x',32)) AND bool_and(timeout_milliseconds=25000)
 FROM net.http_request_queue WHERE id IN (SELECT request_id FROM ops.worker_dispatches)), 'requests target the configured functions URL with the worker header');
SELECT pg_temp.ok(ops.dispatch_workers()=0, 'no second dispatch within min_interval');
UPDATE ops.worker_schedule SET last_dispatched_at=clock_timestamp()-interval '2 hours',asset_retention='30 days',enabled=true
 WHERE worker='cleanup-assets-and-content';
SELECT pg_temp.ok(ops.dispatch_workers()=1, 'cleanup dispatched once when due');
SELECT pg_temp.ok((SELECT abs(extract(epoch FROM (body_text::jsonb->>'asset_before')::timestamptz-(clock_timestamp()-interval '30 days')))<60
 FROM (SELECT convert_from(q.body,'utf8') body_text FROM net.http_request_queue q JOIN ops.worker_dispatches d ON d.request_id=q.id
 WHERE d.worker='cleanup-assets-and-content') x), 'explicit retention becomes an absolute asset_before');
-- Separate statements: a call and a read of its effect must not share a snapshot.
SELECT pg_temp.ok((ops.disable_worker_schedule())->>'outcome'='DISABLED', 'disable succeeds with an active job');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM cron.job WHERE jobname='sporta-workers') AND NOT EXISTS(SELECT FROM ops.worker_schedule WHERE enabled),
 'disable removes the job and every worker');
\else
SELECT pg_temp.rejects($$SELECT ops.enable_worker_schedule(array['provision-invitation'])$$,'55000','enable refused where pg_cron/pg_net/Vault are absent');
SELECT pg_temp.rejects($$SELECT ops.dispatch_workers()$$,'55000','dispatch refused where pg_cron/pg_net/Vault are absent');
\endif
SELECT '1..'||last_value FROM pg_temp.assertion_number;
ROLLBACK;
