-- Storage service owns its schema. The standalone runner supplies a TEST-ONLY substitute.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('academy-private-assets','academy-private-assets',false,2000000,ARRAY['image/png','image/jpeg','image/webp'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=2000000,allowed_mime_types=EXCLUDED.allowed_mime_types;
-- No Storage client policies: only Edge uses the service key after database authorization.

CREATE FUNCTION private.system_context(p_academy uuid,p_rpc text,p_key uuid,p_args jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE r private.command_receipts; h text:=encode(sha256(convert_to(p_args::text,'UTF8')),'hex');
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('3D/'||p_rpc||'/'||p_key::text,0));
 SELECT * INTO r FROM private.command_receipts WHERE actor_ref='3D_WORKER' AND rpc_name=p_rpc AND operation_key=p_key;
 IF FOUND THEN
 IF r.request_hash<>h OR r.academy_id IS DISTINCT FROM p_academy THEN PERFORM private.fail('IDEMPOTENCY_CONFLICT'); END IF;
 RETURN jsonb_build_object('replay',r.result); END IF;
 RETURN jsonb_build_object('operation_id',gen_random_uuid(),'academy_id',p_academy,'rpc',p_rpc,'key',p_key,'hash',h);
END;
$$;
CREATE FUNCTION private.system_finish(p_ctx jsonb,p_result jsonb,p_action text,p_resource uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid:=(p_ctx->>'academy_id')::uuid; op uuid:=(p_ctx->>'operation_id')::uuid;
BEGIN
 INSERT INTO private.command_receipts(id,scope,academy_id,actor_kind,actor_ref,rpc_name,operation_key,request_hash,result,completed_at)
 VALUES(op,CASE WHEN a IS NULL THEN 'PLATFORM' ELSE 'TENANT' END,a,'SYSTEM','3D_WORKER',p_ctx->>'rpc',
 (p_ctx->>'key')::uuid,p_ctx->>'hash',p_result,clock_timestamp());
 INSERT INTO private.audit_log(scope,academy_id,operation_id,effect_key,actor_kind,actor_ref,action,resource_type,resource_id,occurred_at)
 VALUES(CASE WHEN a IS NULL THEN 'PLATFORM' ELSE 'TENANT' END,a,op,'audit','SYSTEM','3D_WORKER',p_action,'3D',p_resource,clock_timestamp());
 RETURN p_result;
END;
$$;
CREATE FUNCTION public.prepare_asset(p_academy uuid,p_usage text,p_tournament uuid,p_mime text,p_size bigint,p_sha256 text,p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE ctx jsonb; v_id uuid:=gen_random_uuid(); v_path text;
BEGIN
 IF p_usage IS NULL OR p_usage NOT IN ('BRANDING','TOURNAMENT_COVER') OR p_mime IS NULL
 OR p_mime NOT IN ('image/png','image/jpeg','image/webp') OR p_size IS NULL OR p_size NOT BETWEEN 1 AND 2000000
 OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' OR (p_usage='TOURNAMENT_COVER')<>(p_tournament IS NOT NULL)
 THEN PERFORM private.fail('INVALID_MEDIA','22023'); END IF;
 PERFORM private.require_permission(p_academy,CASE p_usage WHEN 'BRANDING' THEN 'academy.branding_upload' ELSE 'tournaments.cover_upload' END);
 ctx:=private.cmd_begin(p_academy,'prepare_asset',p_operation_key,jsonb_build_array(p_usage,p_tournament,p_mime,p_size,p_sha256));
 IF ctx ? 'replay' THEN RETURN ctx->'replay'; END IF;
 IF p_tournament IS NOT NULL AND NOT EXISTS(SELECT FROM public.tournaments WHERE academy_id=p_academy AND id=p_tournament AND deleted_at IS NULL)
 THEN PERFORM private.fail('NOT_FOUND','P0002'); END IF;
 v_path:='academies/'||p_academy||CASE p_usage WHEN 'BRANDING' THEN '/branding/' ELSE '/tournaments/'||p_tournament||'/' END||v_id||
 CASE p_mime WHEN 'image/png' THEN '.png' WHEN 'image/jpeg' THEN '.jpg' ELSE '.webp' END;
 INSERT INTO private.academy_assets(id,academy_id,usage,tournament_id,bucket_id,object_path,mime_type,byte_size,sha256,status,uploaded_by,operation_id)
 VALUES(v_id,p_academy,p_usage,p_tournament,'academy-private-assets',v_path,p_mime,p_size,p_sha256,'PENDING',auth.uid(),(ctx->>'operation_id')::uuid);
 PERFORM private.audit(ctx,'audit','asset.prepared','asset',v_id);
 RETURN private.cmd_finish(ctx,jsonb_build_object('asset_id',v_id,'bucket','academy-private-assets','path',v_path));
END;
$$;
CREATE FUNCTION public.authorize_asset_read(p_academy uuid,p_asset uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE a private.academy_assets;
BEGIN
 PERFORM private.require_permission(p_academy,'academy.read');
 SELECT * INTO a FROM private.academy_assets WHERE academy_id=p_academy AND id=p_asset AND status='READY';
 IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND','P0002'); END IF;
 IF a.usage='TOURNAMENT_COVER' THEN PERFORM private.require_permission(p_academy,'tournaments.read'); END IF;
 RETURN jsonb_build_object('bucket',a.bucket_id,'path',a.object_path);
END;
$$;
-- Edge supplies evidence only after decoding the bytes returned by Storage.
CREATE FUNCTION public.svc_finalize_asset(p_asset uuid,p_actor uuid,p_mime text,p_size bigint,p_sha256 text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE a private.academy_assets; ctx jsonb; tenant uuid;
BEGIN
 SELECT academy_id INTO tenant FROM private.academy_assets WHERE id=p_asset;
 PERFORM private.lock_academy(tenant);
 SELECT * INTO a FROM private.academy_assets WHERE id=p_asset FOR UPDATE;
 IF NOT FOUND OR a.uploaded_by IS DISTINCT FROM p_actor OR NOT private.actor_permission(p_actor,a.academy_id,
 CASE a.usage WHEN 'BRANDING' THEN 'academy.branding_upload' ELSE 'tournaments.cover_upload' END) THEN PERFORM private.fail('FORBIDDEN','42501'); END IF;
 IF a.mime_type IS DISTINCT FROM p_mime OR a.byte_size IS DISTINCT FROM p_size OR a.sha256 IS DISTINCT FROM p_sha256
 THEN PERFORM private.fail('INVALID_MEDIA','22023'); END IF;
 IF a.status='READY' THEN RETURN jsonb_build_object('outcome','READY','asset_id',a.id); END IF;
 IF a.status<>'PENDING' THEN PERFORM private.fail('INVALID_STATE'); END IF;
 IF a.usage='TOURNAMENT_COVER' AND NOT EXISTS(SELECT FROM public.tournaments WHERE id=a.tournament_id AND academy_id=a.academy_id AND deleted_at IS NULL)
 THEN PERFORM private.fail('NOT_FOUND','P0002'); END IF;
 ctx:=private.system_context(a.academy_id,'finalize_asset',a.id,jsonb_build_array(a.id,a.sha256));
 UPDATE private.academy_assets SET status='READY',ready_at=clock_timestamp() WHERE id=a.id;
 IF a.usage='BRANDING' THEN UPDATE public.academies SET logo_asset_id=a.id WHERE id=a.academy_id;
 ELSE UPDATE public.tournaments SET cover_asset_id=a.id WHERE academy_id=a.academy_id AND id=a.tournament_id; END IF;
 RETURN private.system_finish(ctx,jsonb_build_object('outcome','READY','asset_id',a.id),'asset.finalized',a.id);
END;
$$;
-- Explicit retention cutoff supplied only by the operator; no invented D28 policy.
CREATE FUNCTION public.svc_claim_asset_cleanup(p_before timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE a private.academy_assets; tenant uuid;
BEGIN
 IF p_before IS NULL OR p_before>=clock_timestamp()-interval '1 day' THEN PERFORM private.fail('INVALID_RETENTION','22023'); END IF;
 -- Same academy -> asset lock order as finalization; skip locked academies.
 SELECT x.academy_id INTO tenant FROM private.academy_assets x JOIN public.academies c ON c.id=x.academy_id
 WHERE x.created_at<p_before AND x.status IN ('PENDING','READY','ORPHANED')
 AND NOT EXISTS(SELECT FROM public.academies WHERE logo_asset_id=x.id)
 AND NOT EXISTS(SELECT FROM public.tournaments WHERE cover_asset_id=x.id)
 ORDER BY x.created_at FOR UPDATE OF c SKIP LOCKED LIMIT 1;
 SELECT * INTO a FROM private.academy_assets x WHERE x.academy_id=tenant AND x.created_at<p_before
 AND x.status IN ('PENDING','READY','ORPHANED')
 AND NOT EXISTS(SELECT FROM public.academies WHERE logo_asset_id=x.id)
 AND NOT EXISTS(SELECT FROM public.tournaments WHERE cover_asset_id=x.id)
 ORDER BY x.created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 UPDATE private.academy_assets SET status='ORPHANED',orphaned_at=coalesce(orphaned_at,clock_timestamp()) WHERE id=a.id;
 RETURN jsonb_build_object('asset_id',a.id,'bucket',a.bucket_id,'path',a.object_path);
END;
$$;
CREATE FUNCTION public.svc_finish_asset_cleanup(p_asset uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE a private.academy_assets; ctx jsonb;
BEGIN
 SELECT * INTO a FROM private.academy_assets WHERE id=p_asset FOR UPDATE;
 IF NOT FOUND THEN PERFORM private.fail('NOT_FOUND'); END IF;
 IF a.status='DELETED' THEN RETURN jsonb_build_object('outcome','DELETED'); END IF;
 IF a.status<>'ORPHANED' OR EXISTS(SELECT FROM public.academies WHERE logo_asset_id=a.id)
 OR EXISTS(SELECT FROM public.tournaments WHERE cover_asset_id=a.id) THEN PERFORM private.fail('ASSET_REFERENCED'); END IF;
 ctx:=private.system_context(a.academy_id,'cleanup_asset',a.id,jsonb_build_array(a.id));
 UPDATE private.academy_assets SET status='DELETED',deleted_at=clock_timestamp() WHERE id=a.id;
 RETURN private.system_finish(ctx,jsonb_build_object('outcome','DELETED'),'asset.deleted',a.id);
END;
$$;
REVOKE ALL ON FUNCTION private.system_context(uuid,text,uuid,jsonb),private.system_finish(jsonb,jsonb,text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.prepare_asset(uuid,text,uuid,text,bigint,text,uuid),public.authorize_asset_read(uuid,uuid),
 public.svc_finalize_asset(uuid,uuid,text,bigint,text),public.svc_claim_asset_cleanup(timestamptz),public.svc_finish_asset_cleanup(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_asset(uuid,text,uuid,text,bigint,text,uuid),public.authorize_asset_read(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_finalize_asset(uuid,uuid,text,bigint,text),public.svc_claim_asset_cleanup(timestamptz),public.svc_finish_asset_cleanup(uuid) TO service_role;
