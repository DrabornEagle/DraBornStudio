-- Fresh Banana Studio schema. Contains no user data or account configuration.
-- Apply only to your own new Supabase project.

CREATE TABLE public.profiles (
 id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 email text, display_name text, avatar_url text, role text NOT NULL DEFAULT 'user' CHECK (role IN ('user','admin')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.authorized_emails (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), email text NOT NULL UNIQUE, is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.folders (
 id text PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 name text NOT NULL, parent_id text REFERENCES public.folders(id) ON DELETE CASCADE, created_at bigint NOT NULL
);
CREATE TABLE public.generations (
 id text PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 prompt text NOT NULL DEFAULT '', url text NOT NULL DEFAULT '', thumbnail_url text, storage_path text, thumbnail_path text,
 type text NOT NULL DEFAULT 'image' CHECK (type IN ('image','video')), image_model text,
 aspect_ratio text, resolution text, created_at bigint NOT NULL,
 folder_id text REFERENCES public.folders(id) ON DELETE SET NULL, is_favorite boolean NOT NULL DEFAULT false,
 reference_images jsonb NOT NULL DEFAULT '[]', status text NOT NULL DEFAULT 'completed', task_id text,
 metadata jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX generations_owner_created ON public.generations(user_id,created_at DESC,id);
CREATE INDEX folders_owner_parent ON public.folders(user_id,parent_id);
CREATE TABLE public.templates (
 id text PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 name text NOT NULL, config jsonb NOT NULL, created_at bigint NOT NULL
);
CREATE TABLE public.reference_images (
 id text PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 data text NOT NULL, mime_type text NOT NULL, name text, created_at bigint NOT NULL
);
CREATE TABLE public.usage_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 action text NOT NULL, model text NOT NULL, prompt text, image_count integer NOT NULL DEFAULT 0,
 estimated_cost numeric, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX usage_owner_created ON public.usage_logs(user_id,created_at);
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC,anon,authenticated;
CREATE FUNCTION private.create_profile() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO public.profiles(id,email,display_name,avatar_url,role)
 VALUES(NEW.id,NEW.email,left(coalesce(NEW.raw_user_meta_data->>'full_name','New user'),100),NULL,'user')
 ON CONFLICT(id) DO NOTHING;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.create_profile() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER create_workspace_profile AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION private.create_profile();
INSERT INTO storage.buckets(id,name,public) VALUES ('media','media',false) ON CONFLICT(id) DO UPDATE SET public=false;


CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS private.security_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
REVOKE ALL ON private.security_migrations FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_authorized()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users u JOIN public.authorized_emails a
      ON lower(btrim(a.email)) = lower(btrim(u.email))
    WHERE u.id = (SELECT auth.uid()) AND a.is_active = true
      AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous, false)
  );
$$;
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_authorized() AND EXISTS (
    SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin'
  );
$$;
REVOKE ALL ON FUNCTION public.is_authorized(), public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_authorized(), public.is_admin() TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS private.legacy_media_owners (
  name text NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (name, user_id)
);
REVOKE ALL ON TABLE private.legacy_media_owners FROM PUBLIC, anon, authenticated;
ALTER TABLE private.legacy_media_owners ENABLE ROW LEVEL SECURITY;
INSERT INTO private.legacy_media_owners(name, user_id)
SELECT o.name, min(g.user_id::text)::uuid
FROM storage.objects o JOIN public.generations g ON (
  o.name = g.storage_path OR o.name = g.thumbnail_path
  OR o.name = g.id || '.png' OR o.name = g.id || '.mp4'
  OR o.name = g.id || '_thumb.png'

)
WHERE o.bucket_id = 'media' AND o.owner_id IS NULL AND g.user_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM private.security_migrations WHERE name='private_gallery_access_v1')
GROUP BY o.name HAVING count(DISTINCT g.user_id)=1
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION private.can_access_media(object_name text, object_owner text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_authorized() AND (
    public.is_admin()
    OR object_owner = (SELECT auth.uid())::text
    OR EXISTS (SELECT 1 FROM private.legacy_media_owners l
      WHERE l.name = object_name AND l.user_id = (SELECT auth.uid()))
  );
$$;
REVOKE ALL ON FUNCTION private.can_access_media(text, text) FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.can_access_media(text, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.register_media_import(p_path text, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_path NOT LIKE p_user_id::text || '/imports/%' OR NOT EXISTS (
    SELECT 1 FROM storage.objects WHERE bucket_id='media' AND name=p_path
  ) THEN
    RAISE EXCEPTION 'Invalid imported media path';
  END IF;
  INSERT INTO private.legacy_media_owners(name,user_id) VALUES (p_path,p_user_id) ON CONFLICT DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.register_media_import(text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_media_import(text,uuid) TO service_role;

DO $$ DECLARE t text; p record; BEGIN
  FOREACH t IN ARRAY ARRAY['authorized_emails','profiles','generations','folders','templates','reference_images','usage_logs'] LOOP
    FOR p IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = t LOOP
      EXECUTE format('DROP POLICY %I ON public.%I', p.policyname, t);
    END LOOP;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.authorized_emails TO authenticated;
CREATE POLICY access_list_read ON public.authorized_emails FOR SELECT TO authenticated
  USING (lower(btrim(email)) = lower(btrim((SELECT auth.jwt()->>'email'))) OR (SELECT public.is_admin()));
CREATE POLICY access_list_insert ON public.authorized_emails FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY access_list_update ON public.authorized_emails FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY access_list_delete ON public.authorized_emails FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (display_name, avatar_url) ON public.profiles TO authenticated;
CREATE POLICY profiles_read ON public.profiles FOR SELECT TO authenticated
  USING ((SELECT public.is_authorized()) AND (id = (SELECT auth.uid()) OR (SELECT public.is_admin())));
CREATE POLICY profiles_edit ON public.profiles FOR UPDATE TO authenticated
  USING ((SELECT public.is_authorized()) AND id = (SELECT auth.uid()))
  WITH CHECK ((SELECT public.is_authorized()) AND id = (SELECT auth.uid()));

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['generations','folders','templates','reference_images'] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
    EXECUTE format('CREATE POLICY active_access_required ON public.%I AS RESTRICTIVE FOR ALL TO public USING ((SELECT public.is_authorized())) WITH CHECK ((SELECT public.is_authorized()))', t);
    EXECUTE format('CREATE POLICY owner_read ON public.%I FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_admin()))', t);
    EXECUTE format('CREATE POLICY owner_insert ON public.%I FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()))', t);
    EXECUTE format('CREATE POLICY owner_update ON public.%I FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()))', t);
    EXECUTE format('CREATE POLICY owner_delete ON public.%I FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_admin()))', t);
  END LOOP;
END $$;
GRANT SELECT, INSERT, DELETE ON public.usage_logs TO authenticated;
CREATE POLICY usage_active ON public.usage_logs AS RESTRICTIVE FOR ALL TO public USING ((SELECT public.is_authorized())) WITH CHECK ((SELECT public.is_authorized()));
CREATE POLICY usage_read ON public.usage_logs FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_admin()));
CREATE POLICY usage_insert ON public.usage_logs FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY usage_delete ON public.usage_logs FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

CREATE TABLE IF NOT EXISTS public.provider_tasks (
  provider text NOT NULL CHECK (provider IN ('fal', 'evolink')),
  task_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, task_id)
);
ALTER TABLE public.provider_tasks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_tasks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.provider_tasks TO authenticated;
GRANT ALL ON public.provider_tasks TO service_role;
DROP POLICY IF EXISTS provider_task_owner_read ON public.provider_tasks;
CREATE POLICY provider_task_owner_read ON public.provider_tasks FOR SELECT TO authenticated
  USING ((SELECT public.is_authorized()) AND (user_id = (SELECT auth.uid()) OR (SELECT public.is_admin())));
WITH historical_tasks AS (
  SELECT 'fal'::text provider, metadata->>'falRequestId' task_id, user_id
  FROM public.generations WHERE nullif(metadata->>'falRequestId','') IS NOT NULL
  UNION ALL
  SELECT CASE WHEN image_model='minimax-h3' OR metadata->>'videoModel'='minimax-h3'
    OR nullif(metadata->>'falEndpoint','') IS NOT NULL OR nullif(metadata->>'falQueueEndpoint','') IS NOT NULL
    THEN 'fal' ELSE 'evolink' END, task_id, user_id
  FROM public.generations WHERE type='video' AND nullif(task_id,'') IS NOT NULL
)
INSERT INTO public.provider_tasks(provider,task_id,user_id)
SELECT provider,task_id,min(user_id::text)::uuid FROM historical_tasks
WHERE user_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM private.security_migrations WHERE name='private_gallery_access_v1'
)
GROUP BY provider,task_id HAVING count(DISTINCT user_id)=1
ON CONFLICT DO NOTHING;
CREATE INDEX IF NOT EXISTS provider_tasks_user_id_idx ON public.provider_tasks(user_id);

DO $$ DECLARE p record; BEGIN
  FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
    AND (qual LIKE '%media%' OR with_check LIKE '%media%') LOOP
    EXECUTE format('DROP POLICY %I ON storage.objects',p.policyname);
  END LOOP;
END $$;
DROP POLICY IF EXISTS media_access_guard ON storage.objects;
CREATE POLICY media_access_guard ON storage.objects AS RESTRICTIVE FOR ALL TO public
USING (bucket_id <> 'media' OR private.can_access_media(name, owner_id))
WITH CHECK (bucket_id <> 'media' OR ((SELECT public.is_authorized()) AND (
  private.can_access_media(name, owner_id)
  OR name LIKE (SELECT auth.uid())::text || '/%'
  OR name LIKE 'openai/' || (SELECT auth.uid())::text || '/%'
)));
CREATE POLICY media_owner_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='media' AND private.can_access_media(name,owner_id));
CREATE POLICY media_owner_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='media' AND (SELECT public.is_authorized()) AND (
    name LIKE (SELECT auth.uid())::text || '/%'
    OR name LIKE 'openai/' || (SELECT auth.uid())::text || '/%'));
CREATE POLICY media_owner_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id='media' AND private.can_access_media(name,owner_id))
  WITH CHECK (bucket_id='media' AND private.can_access_media(name,owner_id));
CREATE POLICY media_owner_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id='media' AND private.can_access_media(name,owner_id));
UPDATE storage.buckets SET public=false WHERE id='media';

INSERT INTO private.security_migrations(name) VALUES ('private_gallery_access_v1') ON CONFLICT DO NOTHING;
NOTIFY pgrst, 'reload schema';

CREATE TABLE public.saved_people (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 40),
  photos jsonb NOT NULL CHECK (jsonb_typeof(photos) = 'array' AND jsonb_array_length(photos) BETWEEN 1 AND 16 AND octet_length(photos::text) <= 20971520),
  is_me boolean NOT NULL DEFAULT false,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at timestamptz
);
CREATE INDEX saved_people_owner_created ON public.saved_people(user_id, created_at DESC) WHERE deleted_at IS NULL;
ALTER TABLE public.saved_people ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.saved_people FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.saved_people TO authenticated;
GRANT ALL ON public.saved_people TO service_role;
CREATE POLICY active_access_required ON public.saved_people AS RESTRICTIVE FOR ALL TO public
  USING ((SELECT public.is_authorized())) WITH CHECK ((SELECT public.is_authorized()));
CREATE POLICY owner_read ON public.saved_people FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY owner_insert ON public.saved_people FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY owner_update ON public.saved_people FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.get_gallery_search_people(
  p_owner_id uuid, p_after_id text DEFAULT NULL, p_limit integer DEFAULT 500
) RETURNS TABLE (id text, people text[])
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  WITH page AS (
    SELECT g.id, g.reference_images
    FROM public.generations g
    WHERE g.user_id = p_owner_id
      AND (p_after_id IS NULL OR g.id > p_after_id)
      AND (SELECT public.is_authorized())
      AND (p_owner_id = (SELECT auth.uid()) OR (SELECT public.is_admin()))
    ORDER BY g.id
    LIMIT greatest(1, least(coalesce(p_limit, 500), 500))
  )
  SELECT page.id, ARRAY(
    SELECT DISTINCT left(btrim(regexp_replace(ref->>'personName', E'[\\r\\n\\t]', ' ', 'g')), 40)
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(page.reference_images::jsonb) = 'array' THEN page.reference_images::jsonb ELSE '[]'::jsonb END) ref
    WHERE coalesce(ref->>'isFirstFrame', 'false') <> 'true'
      AND coalesce(ref->>'isLastFrame', 'false') <> 'true'
      AND coalesce(ref->>'isDraftImage', 'false') <> 'true'
      AND coalesce(ref->>'isVideoContext', 'false') <> 'true'
      AND (ref->>'personId' ~ '^[1-9][0-9]{0,3}$' OR ref->>'isSubjectImage' = 'true' OR ref->>'isSecondPerson' = 'true')
      AND nullif(btrim(ref->>'personName'), '') IS NOT NULL
  ) AS people
  FROM page ORDER BY page.id;
$$;
REVOKE ALL ON FUNCTION public.get_gallery_search_people(uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_gallery_search_people(uuid, text, integer) TO authenticated;

ALTER TABLE public.generations ADD COLUMN search_people text[];
COMMENT ON COLUMN public.generations.search_people IS 'Derived person names for gallery search; maintained from reference_images by trigger.';

CREATE FUNCTION public.extract_gallery_search_people(p_references jsonb)
RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = '' AS $$
  SELECT ARRAY(
    SELECT DISTINCT left(btrim(regexp_replace(ref->>'personName', E'[\\r\\n\\t]', ' ', 'g')), 40)
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_references) = 'array' THEN p_references ELSE '[]'::jsonb END) ref
    WHERE coalesce(ref->>'isFirstFrame', 'false') <> 'true'
      AND coalesce(ref->>'isLastFrame', 'false') <> 'true'
      AND coalesce(ref->>'isDraftImage', 'false') <> 'true'
      AND coalesce(ref->>'isVideoContext', 'false') <> 'true'
      AND (ref->>'personId' ~ '^[1-9][0-9]{0,3}$' OR ref->>'isSubjectImage' = 'true' OR ref->>'isSecondPerson' = 'true')
      AND nullif(btrim(ref->>'personName'), '') IS NOT NULL
  );
$$;
REVOKE ALL ON FUNCTION public.extract_gallery_search_people(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extract_gallery_search_people(jsonb) TO authenticated, service_role;

CREATE FUNCTION public.sync_generation_search_people()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  NEW.search_people := public.extract_gallery_search_people(NEW.reference_images);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_generation_search_people() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_generation_search_people() TO authenticated, service_role;

CREATE TRIGGER sync_generation_search_people
BEFORE INSERT OR UPDATE OF reference_images, search_people ON public.generations
FOR EACH ROW EXECUTE FUNCTION public.sync_generation_search_people();

CREATE OR REPLACE FUNCTION public.get_gallery_search_people(
  p_owner_id uuid, p_after_id text DEFAULT NULL, p_limit integer DEFAULT 500
) RETURNS TABLE (id text, people text[])
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT g.id, coalesce(g.search_people, public.extract_gallery_search_people(g.reference_images))
  FROM public.generations g
  WHERE g.user_id = p_owner_id
    AND (p_after_id IS NULL OR g.id > p_after_id)
    AND (SELECT public.is_authorized())
    AND (p_owner_id = (SELECT auth.uid()) OR (SELECT public.is_admin()))
  ORDER BY g.id
  LIMIT greatest(1, least(coalesce(p_limit, 500), 500));
$$;
REVOKE ALL ON FUNCTION public.get_gallery_search_people(uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_gallery_search_people(uuid, text, integer) TO authenticated;


UPDATE public.generations SET search_people = ARRAY[]::text[] WHERE search_people IS NULL;

CREATE TABLE public.folder_shares (
  folder_id text PRIMARY KEY REFERENCES public.folders(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.folder_shares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.folder_shares FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.folder_shares TO service_role;

CREATE INDEX IF NOT EXISTS generations_folder_share_page
  ON public.generations(user_id, folder_id, created_at DESC, id DESC) WHERE type = 'image';

CREATE FUNCTION public.resolve_folder_share(p_token_hash text, p_offset integer DEFAULT 0, p_media_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH shared AS (
    SELECT f.id, f.name, f.user_id, s.expires_at
    FROM public.folder_shares s
    JOIN public.folders f ON f.id = s.folder_id AND f.user_id = s.user_id
    JOIN auth.users u ON u.id = s.user_id
    WHERE s.token_hash = p_token_hash AND s.expires_at > now()
      AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous, false)
      AND EXISTS (SELECT 1 FROM public.authorized_emails a
        WHERE lower(btrim(a.email)) = lower(btrim(u.email)) AND a.is_active)
      AND p_offset BETWEEN 0 AND 1000000
  ), media AS (
    SELECT g.id, g.created_at, original.name AS storage_path, thumbnail.name AS thumbnail_path
    FROM shared s
    JOIN public.generations g ON g.folder_id = s.id AND g.user_id = s.user_id
    JOIN storage.objects original ON original.bucket_id = 'media'
      AND original.name = coalesce(nullif(g.storage_path, ''), g.id || '.png')
      AND (original.owner_id = s.user_id::text OR EXISTS (
        SELECT 1 FROM private.legacy_media_owners l WHERE l.name = original.name AND l.user_id = s.user_id))
      AND original.metadata->>'mimetype' IN ('image/png', 'image/jpeg', 'image/webp', 'image/avif')
    LEFT JOIN storage.objects thumbnail ON thumbnail.bucket_id = 'media'
      AND thumbnail.name = coalesce(nullif(g.thumbnail_path, ''), g.id || '_thumb.png')
      AND (thumbnail.owner_id = s.user_id::text OR EXISTS (
        SELECT 1 FROM private.legacy_media_owners l WHERE l.name = thumbnail.name AND l.user_id = s.user_id))
      AND thumbnail.metadata->>'mimetype' IN ('image/png', 'image/jpeg', 'image/webp', 'image/avif')
    WHERE g.type = 'image' AND (g.status IS NULL OR g.status = 'completed')
      AND (p_media_id IS NULL OR g.id = p_media_id)
    ORDER BY g.created_at DESC, g.id DESC
    LIMIT 49 OFFSET p_offset
  )
  SELECT jsonb_build_object('name', s.name, 'expiresAt', s.expires_at, 'images', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', m.id, 'storagePath', m.storage_path,
      'thumbnailPath', m.thumbnail_path) ORDER BY m.created_at DESC, m.id DESC) FROM media m
  ), '[]'::jsonb)) FROM shared s;
$$;
REVOKE ALL ON FUNCTION public.resolve_folder_share(text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_folder_share(text, integer, text) TO service_role;

CREATE TABLE public.text_model_defaults (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  model text NOT NULL CHECK (model IN ('gemini-3.8-flash', 'gpt-6-astra')),
  gemini_thinking text NOT NULL CHECK (gemini_thinking IN ('LOW', 'MEDIUM', 'HIGH')),
  astra_reasoning text NOT NULL CHECK (astra_reasoning IN ('low', 'medium', 'high', 'xhigh', 'max')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.text_model_defaults(model, gemini_thinking, astra_reasoning)
VALUES ('gemini-3.8-flash', 'MEDIUM', 'medium');

CREATE TABLE public.user_text_model_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  model text NOT NULL CHECK (model IN ('gemini-3.8-flash', 'gpt-6-astra')),
  gemini_thinking text NOT NULL CHECK (gemini_thinking IN ('LOW', 'MEDIUM', 'HIGH')),
  astra_reasoning text NOT NULL CHECK (astra_reasoning IN ('low', 'medium', 'high', 'xhigh', 'max')),
  global_revision bigint NOT NULL CHECK (global_revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.text_model_defaults ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_text_model_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.text_model_defaults, public.user_text_model_preferences FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.text_model_defaults, public.user_text_model_preferences TO service_role;

CREATE FUNCTION public.get_text_model_preferences()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_authorized() THEN
    RAISE EXCEPTION 'Application access required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'model', coalesce(p.model, d.model),
    'thinkingLevel', coalesce(p.gemini_thinking, d.gemini_thinking),
    'reasoningEffort', coalesce(p.astra_reasoning, d.astra_reasoning),
    'source', CASE WHEN p.user_id IS NULL THEN 'all' ELSE 'personal' END,
    'revision', d.revision, 'canSaveAll', public.is_admin()
  ) INTO result
  FROM public.text_model_defaults d
  LEFT JOIN public.user_text_model_preferences p ON p.user_id = auth.uid() AND p.global_revision = d.revision
  WHERE d.singleton;
  RETURN result;
END;
$$;

CREATE FUNCTION public.save_text_model_preferences(p_scope text, p_model text, p_gemini_thinking text, p_astra_reasoning text, p_expected_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE current_revision bigint;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_user_id OR NOT public.is_authorized() THEN
    RAISE EXCEPTION 'Application access required' USING ERRCODE = '42501';
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('me', 'all')
    OR p_model IS NULL OR p_model NOT IN ('gemini-3.8-flash', 'gpt-6-astra')
    OR p_gemini_thinking IS NULL OR p_gemini_thinking NOT IN ('LOW', 'MEDIUM', 'HIGH')
    OR p_astra_reasoning IS NULL OR p_astra_reasoning NOT IN ('low', 'medium', 'high', 'xhigh', 'max') THEN
    RAISE EXCEPTION 'Invalid model settings' USING ERRCODE = '22023';
  END IF;
  IF p_scope = 'all' THEN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
    UPDATE public.text_model_defaults SET model = p_model, gemini_thinking = p_gemini_thinking,
      astra_reasoning = p_astra_reasoning, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
    WHERE singleton;
  ELSE
    SELECT revision INTO STRICT current_revision FROM public.text_model_defaults WHERE singleton FOR SHARE;
    INSERT INTO public.user_text_model_preferences(user_id, model, gemini_thinking, astra_reasoning, global_revision)
    VALUES (auth.uid(), p_model, p_gemini_thinking, p_astra_reasoning, current_revision)
    ON CONFLICT (user_id) DO UPDATE SET model = EXCLUDED.model, gemini_thinking = EXCLUDED.gemini_thinking,
      astra_reasoning = EXCLUDED.astra_reasoning, global_revision = EXCLUDED.global_revision, updated_at = now();
  END IF;
  RETURN public.get_text_model_preferences();
END;
$$;
REVOKE ALL ON FUNCTION public.get_text_model_preferences(), public.save_text_model_preferences(text,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_text_model_preferences(), public.save_text_model_preferences(text,text,text,text,uuid) TO authenticated;

CREATE TABLE private.openai_requests (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('image', 'text')),
  generation_id text,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  outcome text NOT NULL DEFAULT 'accepted' CHECK (outcome IN ('accepted', 'completed', 'failed', 'rejected')),
  provider_request_id text,
  provider_status integer,
  CHECK (generation_id IS NULL OR generation_id ~ '^[a-zA-Z0-9_-]{1,128}$'),
  CHECK (provider_request_id IS NULL OR provider_request_id ~ '^[a-zA-Z0-9_-]{1,128}$')
);
CREATE INDEX openai_requests_time ON private.openai_requests (started_at);
CREATE INDEX openai_requests_user_time ON private.openai_requests (user_id, started_at);
ALTER TABLE private.openai_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.openai_requests FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.start_openai_request(p_id uuid, p_user_id uuid, p_session_id uuid, p_kind text, p_generation_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_now timestamptz;
  v_user_minute integer; v_user_day integer; v_user_active integer;
  v_global_minute integer; v_global_day integer; v_global_active integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users u JOIN public.authorized_emails a
      ON lower(btrim(a.email)) = lower(btrim(u.email))
    JOIN auth.sessions s ON s.user_id = u.id AND s.id = p_session_id
    WHERE u.id = p_user_id AND a.is_active = true
      AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous, false)
      AND (s.not_after IS NULL OR s.not_after > clock_timestamp())
  ) THEN RETURN jsonb_build_object('allowed', false, 'reason', 'session'); END IF;
  IF p_kind NOT IN ('image', 'text') OR p_kind IS NULL THEN RAISE EXCEPTION 'Invalid request kind'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(711902, 1);
  v_now := clock_timestamp();
  SELECT count(*) FILTER (WHERE started_at > v_now - interval '1 minute'), count(*),
    count(*) FILTER (WHERE outcome = 'accepted' AND started_at > v_now - interval '5 minutes')
  INTO v_global_minute, v_global_day, v_global_active
  FROM private.openai_requests WHERE started_at > v_now - interval '24 hours';
  SELECT count(*) FILTER (WHERE started_at > v_now - interval '1 minute'), count(*),
    count(*) FILTER (WHERE outcome = 'accepted' AND started_at > v_now - interval '5 minutes')
  INTO v_user_minute, v_user_day, v_user_active
  FROM private.openai_requests WHERE user_id = p_user_id AND started_at > v_now - interval '24 hours';
  IF v_user_day >= 400 OR v_global_day >= 1200 THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'daily', 'retry_after', 3600);
  END IF;
  IF v_user_minute >= 60 OR v_global_minute >= 150 OR v_user_active >= 24 OR v_global_active >= 48 THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'rate', 'retry_after', 60);
  END IF;
  INSERT INTO private.openai_requests(id,user_id,session_id,kind,generation_id,started_at)
    VALUES (p_id,p_user_id,p_session_id,p_kind,p_generation_id,v_now);
  RETURN jsonb_build_object('allowed', true);
END;
$$;
CREATE FUNCTION public.finish_openai_request(p_id uuid, p_outcome text, p_provider_request_id text DEFAULT NULL, p_provider_status integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_outcome NOT IN ('completed', 'failed', 'rejected') OR p_outcome IS NULL THEN RAISE EXCEPTION 'Invalid request outcome'; END IF;
  UPDATE private.openai_requests SET outcome=p_outcome, finished_at=clock_timestamp(),
    provider_request_id=p_provider_request_id, provider_status=p_provider_status
  WHERE id=p_id AND outcome='accepted';
END;
$$;
REVOKE ALL ON FUNCTION public.start_openai_request(uuid,uuid,uuid,text,text), public.finish_openai_request(uuid,text,text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_openai_request(uuid,uuid,uuid,text,text), public.finish_openai_request(uuid,text,text,integer) TO service_role;



ALTER TABLE public.usage_logs DROP CONSTRAINT IF EXISTS usage_logs_action_check;
ALTER TABLE public.usage_logs ADD CONSTRAINT usage_logs_action_check
  CHECK (action IN ('generate', 'enhance', 'brainstorm', 'variation', 'video_generate', 'video_enhance', 'edit_plan'));

ALTER TABLE public.text_model_defaults
  DROP CONSTRAINT text_model_defaults_model_check, DROP CONSTRAINT text_model_defaults_astra_reasoning_check;
ALTER TABLE public.user_text_model_preferences
  DROP CONSTRAINT user_text_model_preferences_model_check, DROP CONSTRAINT user_text_model_preferences_astra_reasoning_check;
ALTER TABLE public.text_model_defaults RENAME COLUMN astra_reasoning TO openai_reasoning;
ALTER TABLE public.user_text_model_preferences RENAME COLUMN astra_reasoning TO openai_reasoning;

UPDATE public.user_text_model_preferences SET model = 'gpt-6.1-sol' WHERE model = 'gpt-6-astra';
UPDATE public.text_model_defaults SET model = 'gpt-6.1-sol', openai_reasoning = 'high',
  revision = revision + 1, updated_by = NULL, updated_at = now()
WHERE singleton;

ALTER TABLE public.text_model_defaults
  ADD CONSTRAINT text_model_defaults_model_check CHECK (model IN ('gemini-3.8-flash', 'gpt-6.1-sol')),
  ADD CONSTRAINT text_model_defaults_openai_reasoning_check CHECK (openai_reasoning IN ('low', 'medium', 'high', 'xhigh', 'max'));
ALTER TABLE public.user_text_model_preferences
  ADD CONSTRAINT user_text_model_preferences_model_check CHECK (model IN ('gemini-3.8-flash', 'gpt-6.1-sol')),
  ADD CONSTRAINT user_text_model_preferences_openai_reasoning_check CHECK (openai_reasoning IN ('low', 'medium', 'high', 'xhigh', 'max'));

CREATE OR REPLACE FUNCTION public.get_text_model_preferences()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_authorized() THEN
    RAISE EXCEPTION 'Application access required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'model', coalesce(p.model, d.model),
    'thinkingLevel', coalesce(p.gemini_thinking, d.gemini_thinking),
    'reasoningEffort', coalesce(p.openai_reasoning, d.openai_reasoning),
    'source', CASE WHEN p.user_id IS NULL THEN 'all' ELSE 'personal' END,
    'revision', d.revision, 'canSaveAll', public.is_admin()
  ) INTO result
  FROM public.text_model_defaults d
  LEFT JOIN public.user_text_model_preferences p ON p.user_id = auth.uid() AND p.global_revision = d.revision
  WHERE d.singleton;
  RETURN result;
END;
$$;

DROP FUNCTION public.save_text_model_preferences(text, text, text, text, uuid);
CREATE FUNCTION public.save_text_model_preferences(p_scope text, p_model text, p_gemini_thinking text, p_openai_reasoning text, p_expected_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE current_revision bigint;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_user_id OR NOT public.is_authorized() THEN
    RAISE EXCEPTION 'Application access required' USING ERRCODE = '42501';
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('me', 'all')
    OR p_model IS NULL OR p_model NOT IN ('gemini-3.8-flash', 'gpt-6.1-sol')
    OR p_gemini_thinking IS NULL OR p_gemini_thinking NOT IN ('LOW', 'MEDIUM', 'HIGH')
    OR p_openai_reasoning IS NULL OR p_openai_reasoning NOT IN ('low', 'medium', 'high', 'xhigh', 'max') THEN
    RAISE EXCEPTION 'Invalid model settings' USING ERRCODE = '22023';
  END IF;
  IF p_scope = 'all' THEN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
    UPDATE public.text_model_defaults SET model = p_model, gemini_thinking = p_gemini_thinking,
      openai_reasoning = p_openai_reasoning, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
    WHERE singleton;
  ELSE
    SELECT revision INTO STRICT current_revision FROM public.text_model_defaults WHERE singleton FOR SHARE;
    INSERT INTO public.user_text_model_preferences(user_id, model, gemini_thinking, openai_reasoning, global_revision)
    VALUES (auth.uid(), p_model, p_gemini_thinking, p_openai_reasoning, current_revision)
    ON CONFLICT (user_id) DO UPDATE SET model = EXCLUDED.model, gemini_thinking = EXCLUDED.gemini_thinking,
      openai_reasoning = EXCLUDED.openai_reasoning, global_revision = EXCLUDED.global_revision, updated_at = now();
  END IF;
  RETURN public.get_text_model_preferences();
END;
$$;
REVOKE ALL ON FUNCTION public.get_text_model_preferences(), public.save_text_model_preferences(text,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_text_model_preferences(), public.save_text_model_preferences(text,text,text,text,uuid) TO authenticated;

ALTER TABLE public.text_model_defaults DROP CONSTRAINT text_model_defaults_model_check;
ALTER TABLE public.user_text_model_preferences DROP CONSTRAINT user_text_model_preferences_model_check;
ALTER TABLE public.text_model_defaults ADD CONSTRAINT text_model_defaults_model_check
  CHECK (model IN ('gemini-3.8-flash','gpt-6.1-sol','anthropic/claude-opus-5.5'));
ALTER TABLE public.user_text_model_preferences ADD CONSTRAINT user_text_model_preferences_model_check
  CHECK (model IN ('gemini-3.8-flash','gpt-6.1-sol','anthropic/claude-opus-5.5'));

CREATE OR REPLACE FUNCTION public.save_text_model_preferences(p_scope text, p_model text, p_gemini_thinking text, p_openai_reasoning text, p_expected_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE current_revision bigint;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_user_id OR NOT public.is_authorized() THEN
    RAISE EXCEPTION 'Application access required' USING ERRCODE = '42501';
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('me','all')
    OR p_model IS NULL OR p_model NOT IN ('gemini-3.8-flash','gpt-6.1-sol','anthropic/claude-opus-5.5')
    OR p_gemini_thinking IS NULL OR p_gemini_thinking NOT IN ('LOW','MEDIUM','HIGH')
    OR p_openai_reasoning IS NULL OR p_openai_reasoning NOT IN ('low','medium','high','xhigh','max') THEN
    RAISE EXCEPTION 'Invalid model settings' USING ERRCODE = '22023';
  END IF;
  IF p_scope = 'all' THEN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
    UPDATE public.text_model_defaults SET model = p_model, gemini_thinking = p_gemini_thinking,
      openai_reasoning = p_openai_reasoning, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
    WHERE singleton;
  ELSE
    SELECT revision INTO STRICT current_revision FROM public.text_model_defaults WHERE singleton FOR SHARE;
    INSERT INTO public.user_text_model_preferences(user_id,model,gemini_thinking,openai_reasoning,global_revision)
    VALUES (auth.uid(),p_model,p_gemini_thinking,p_openai_reasoning,current_revision)
    ON CONFLICT (user_id) DO UPDATE SET model = EXCLUDED.model, gemini_thinking = EXCLUDED.gemini_thinking,
      openai_reasoning = EXCLUDED.openai_reasoning, global_revision = EXCLUDED.global_revision, updated_at = now();
  END IF;
  RETURN public.get_text_model_preferences();
END;
$$;
REVOKE ALL ON FUNCTION public.save_text_model_preferences(text,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_text_model_preferences(text,text,text,text,uuid) TO authenticated;
UPDATE public.text_model_defaults SET model = 'anthropic/claude-opus-5.5',
  revision = revision + 1, updated_by = NULL, updated_at = now() WHERE singleton;

CREATE TABLE private.image_jobs (
  id text PRIMARY KEY CHECK (id ~ '^[a-zA-Z0-9_-]{1,128}$'),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  sequence bigint GENERATED ALWAYS AS IDENTITY,
  state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','preparing','dispatched','completed','failed')),
  claim_token uuid,
  audit_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  not_before timestamptz NOT NULL DEFAULT clock_timestamp(),
  lease_until timestamptz,
  dispatched_at timestamptz,
  published_at timestamptz,
  finished_at timestamptz
);
CREATE INDEX image_jobs_pending ON private.image_jobs (state, not_before, sequence);
CREATE INDEX image_jobs_owner ON private.image_jobs (user_id, state);
ALTER TABLE private.image_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.image_jobs FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.image_job_authorized(p_user uuid, p_session uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users u JOIN public.authorized_emails a
      ON lower(btrim(a.email)) = lower(btrim(u.email))
    JOIN auth.sessions s ON s.user_id=u.id AND s.id=p_session
    WHERE u.id=p_user AND a.is_active AND u.email_confirmed_at IS NOT NULL
      AND NOT coalesce(u.is_anonymous,false) AND (s.not_after IS NULL OR s.not_after>now())
  );
$$;
REVOKE ALL ON FUNCTION private.image_job_authorized(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.enqueue_image_job(p_user_id uuid, p_session_id uuid, p_id text, p_payload jsonb, p_metadata jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs; g public.generations; stamp bigint;
BEGIN
  IF NOT private.image_job_authorized(p_user_id,p_session_id) THEN RETURN jsonb_build_object('error','session'); END IF;
  IF p_id IS NULL OR p_id !~ '^[a-zA-Z0-9_-]{1,128}$' OR jsonb_typeof(p_payload) <> 'object'
    OR octet_length(p_payload::text)>262144 THEN RAISE EXCEPTION 'Invalid image job'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(711902,2);
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id;
  IF FOUND THEN
    IF j.user_id<>p_user_id THEN RETURN jsonb_build_object('error','conflict'); END IF;
    RETURN jsonb_build_object('id',j.id,'state',j.state,'created',false);
  END IF;
  SELECT * INTO g FROM public.generations WHERE id=p_id;
  IF FOUND THEN RETURN jsonb_build_object('error','exists'); END IF;
  IF (SELECT count(*) FROM private.image_jobs WHERE user_id=p_user_id AND state IN ('queued','preparing','dispatched'))>=500
    OR (SELECT count(*) FROM private.image_jobs WHERE state IN ('queued','preparing','dispatched'))>=2000
    THEN RETURN jsonb_build_object('error','full'); END IF;
  stamp := floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
  INSERT INTO private.image_jobs(id,user_id,session_id,payload) VALUES(p_id,p_user_id,p_session_id,p_payload);
  INSERT INTO public.generations(id,user_id,prompt,url,type,aspect_ratio,resolution,image_model,created_at,folder_id,is_favorite,reference_images,status,metadata)
    VALUES(p_id,p_user_id,p_payload->>'displayPrompt','','image',p_payload->>'aspectRatio',p_payload->>'resolution',
      p_payload->>'model',stamp,nullif(p_payload->>'folderId',''),false,coalesce(p_payload->'referenceImages','[]'::jsonb),'pending',
      coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('imageQueue',jsonb_build_object('version',1,'queuedAt',stamp),'imageStage','queued'));
  RETURN jsonb_build_object('id',p_id,'state','queued','created',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.start_openai_request(p_id uuid, p_user_id uuid, p_session_id uuid, p_kind text, p_generation_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_now timestamptz; v_user_minute integer; v_user_day integer; v_user_active integer;
  v_global_minute integer; v_global_day integer; v_global_active integer;
BEGIN
  IF NOT private.image_job_authorized(p_user_id,p_session_id) THEN RETURN jsonb_build_object('allowed',false,'reason','session'); END IF;
  IF p_kind NOT IN ('image','text') OR p_kind IS NULL THEN RAISE EXCEPTION 'Invalid request kind'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(711902,1);
  IF p_kind='image' AND p_generation_id IS NOT NULL AND (EXISTS (
    SELECT 1 FROM private.openai_requests WHERE user_id=p_user_id AND generation_id=p_generation_id
      AND kind='image' AND outcome<>'rejected'
  ) OR EXISTS (SELECT 1 FROM private.image_jobs WHERE id=p_generation_id AND user_id=p_user_id AND dispatched_at IS NOT NULL))
    THEN RETURN jsonb_build_object('allowed',false,'reason','duplicate'); END IF;
  v_now := clock_timestamp();
  SELECT count(*) FILTER(WHERE started_at>v_now-interval '1 minute'),count(*),
    count(*) FILTER(WHERE outcome='accepted' AND started_at>v_now-interval '5 minutes')
    INTO v_global_minute,v_global_day,v_global_active FROM private.openai_requests WHERE started_at>v_now-interval '24 hours';
  SELECT count(*) FILTER(WHERE started_at>v_now-interval '1 minute'),count(*),
    count(*) FILTER(WHERE outcome='accepted' AND started_at>v_now-interval '5 minutes')
    INTO v_user_minute,v_user_day,v_user_active FROM private.openai_requests WHERE user_id=p_user_id AND started_at>v_now-interval '24 hours';
  IF v_user_day>=400 OR v_global_day>=1200 THEN RETURN jsonb_build_object('allowed',false,'reason','daily','retry_after',3600); END IF;
  IF v_user_minute>=60 OR v_global_minute>=150 OR v_user_active>=24 OR v_global_active>=48
    THEN RETURN jsonb_build_object('allowed',false,'reason','rate','retry_after',60); END IF;
  INSERT INTO private.openai_requests(id,user_id,session_id,kind,generation_id,started_at)
    VALUES(p_id,p_user_id,p_session_id,p_kind,p_generation_id,v_now);
  RETURN jsonb_build_object('allowed',true);
END;
$$;

CREATE FUNCTION public.claim_image_job(p_id text, p_user_id uuid, p_claim uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs; admission jsonb; audit uuid; busy integer; ahead integer;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(711902,1);
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id AND user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('action','stop'); END IF;
  IF j.state IN ('completed','failed') THEN RETURN jsonb_build_object('action','stop'); END IF;
  IF j.state='dispatched' THEN RETURN jsonb_build_object('action','observe','claim',j.claim_token,'audit',j.audit_id,'dispatchedAt',j.dispatched_at); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.generations WHERE id=p_id AND user_id=j.user_id) THEN
    UPDATE private.image_jobs SET state='failed',finished_at=clock_timestamp() WHERE id=p_id;
    RETURN jsonb_build_object('action','stop');
  END IF;
  IF NOT private.image_job_authorized(j.user_id,j.session_id) THEN
    UPDATE private.image_jobs SET state='failed',finished_at=clock_timestamp() WHERE id=p_id;
    UPDATE public.generations SET status='failed',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('error','Queued generation cancelled because access was revoked.') WHERE id=p_id AND user_id=j.user_id;
    RETURN jsonb_build_object('action','stop');
  END IF;
  IF j.not_before>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',greatest(1,ceil(extract(epoch FROM j.not_before-clock_timestamp())))); END IF;
  IF j.state='preparing' AND j.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',30); END IF;
  IF j.state='preparing' AND j.audit_id IS NOT NULL THEN PERFORM public.finish_openai_request(j.audit_id,'rejected'); END IF;
  SELECT count(*) INTO busy FROM private.image_jobs WHERE user_id=j.user_id AND id<>p_id
    AND ((state='preparing' AND lease_until>clock_timestamp()) OR (state='dispatched' AND dispatched_at>clock_timestamp()-interval '330 seconds'));
  SELECT count(*) INTO ahead FROM private.image_jobs WHERE user_id=j.user_id AND state='queued'
    AND not_before<=clock_timestamp() AND sequence<j.sequence;
  IF busy>=8 OR ahead>=8-busy THEN RETURN jsonb_build_object('action','wait','retryAfter',30); END IF;
  audit := gen_random_uuid();
  admission := public.start_openai_request(audit,j.user_id,j.session_id,'image',p_id);
  IF NOT (admission->>'allowed')::boolean THEN
    IF admission->>'reason'='duplicate' THEN
      UPDATE private.image_jobs SET state='dispatched',dispatched_at=clock_timestamp(),claim_token=p_claim WHERE id=p_id;
      RETURN jsonb_build_object('action','observe','claim',p_claim,'dispatchedAt',clock_timestamp());
    END IF;
    UPDATE private.image_jobs SET state='queued',not_before=clock_timestamp()+make_interval(secs=>coalesce((admission->>'retry_after')::integer,60)),lease_until=NULL WHERE id=p_id;
    RETURN jsonb_build_object('action','wait','retryAfter',coalesce((admission->>'retry_after')::integer,60));
  END IF;
  UPDATE private.image_jobs SET state='preparing',claim_token=p_claim,audit_id=audit,lease_until=clock_timestamp()+interval '120 seconds' WHERE id=p_id;
  RETURN jsonb_build_object('action','prepare','claim',p_claim,'audit',audit,'payload',j.payload);
END;
$$;

CREATE FUNCTION public.dispatch_image_job(p_id text,p_claim uuid,p_metadata jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs;
BEGIN
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id FOR UPDATE;
  IF NOT FOUND OR j.state<>'preparing' OR j.claim_token IS DISTINCT FROM p_claim OR j.lease_until<=clock_timestamp()
    OR NOT private.image_job_authorized(j.user_id,j.session_id)
    OR NOT EXISTS(SELECT 1 FROM public.generations WHERE id=p_id AND user_id=j.user_id) THEN RETURN false; END IF;
  UPDATE private.image_jobs SET state='dispatched',dispatched_at=clock_timestamp(),lease_until=NULL WHERE id=p_id;
  UPDATE public.generations SET status='processing',metadata=coalesce(metadata,'{}'::jsonb)||p_metadata||jsonb_build_object('imageStage','generating')
    WHERE id=p_id AND user_id=j.user_id;
  RETURN true;
END;
$$;

CREATE FUNCTION public.finish_image_job(p_id text,p_claim uuid,p_success boolean,p_metadata jsonb DEFAULT NULL,p_storage_path text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs;
BEGIN
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id FOR UPDATE;
  IF NOT FOUND OR j.claim_token IS DISTINCT FROM p_claim OR j.state IN ('completed','failed') THEN RETURN; END IF;
  UPDATE private.image_jobs SET state=CASE WHEN p_success THEN 'completed' ELSE 'failed' END,finished_at=clock_timestamp() WHERE id=p_id;
  IF p_success THEN
    UPDATE public.generations SET status='completed',storage_path=coalesce(p_storage_path,storage_path),
      metadata=(coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb))-'error'-'imageStage' WHERE id=p_id AND user_id=j.user_id;
  ELSE
    UPDATE public.generations SET status='failed',metadata=(coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb))||
      jsonb_build_object('error',coalesce(p_error,'The worker was interrupted. Recover the saved image; generation was not repeated.'))
      WHERE id=p_id AND user_id=j.user_id AND status<>'completed';
  END IF;
END;
$$;

CREATE FUNCTION public.image_job_outbox(p_limit integer DEFAULT 40)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'userId',user_id)),'[]'::jsonb) FROM (
    SELECT id,user_id FROM private.image_jobs WHERE
      (published_at IS NULL OR published_at<clock_timestamp()-interval '5 minutes') AND (
        (state='queued' AND not_before<=clock_timestamp()) OR
        (state='preparing' AND lease_until<clock_timestamp()) OR
        (state='dispatched' AND dispatched_at<clock_timestamp()-interval '330 seconds'))
      ORDER BY sequence LIMIT least(greatest(p_limit,1),100)
  ) jobs;
$$;
CREATE FUNCTION public.mark_image_job_published(p_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE private.image_jobs SET published_at=clock_timestamp() WHERE id=p_id;
$$;

REVOKE ALL ON FUNCTION public.enqueue_image_job(uuid,uuid,text,jsonb,jsonb),public.claim_image_job(text,uuid,uuid),
  public.dispatch_image_job(text,uuid,jsonb),public.finish_image_job(text,uuid,boolean,jsonb,text,text),
  public.image_job_outbox(integer),public.mark_image_job_published(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_image_job(uuid,uuid,text,jsonb,jsonb),public.claim_image_job(text,uuid,uuid),
  public.dispatch_image_job(text,uuid,jsonb),public.finish_image_job(text,uuid,boolean,jsonb,text,text),
  public.image_job_outbox(integer),public.mark_image_job_published(text) TO service_role;

CREATE TABLE private.image_provider_cooldown (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  not_before timestamptz NOT NULL DEFAULT '-infinity'
);
INSERT INTO private.image_provider_cooldown(singleton) VALUES(true);
ALTER TABLE private.image_provider_cooldown ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.image_provider_cooldown FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.claim_image_job(p_id text, p_user_id uuid, p_claim uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs; admission jsonb; audit uuid; busy integer; ahead integer; cooldown timestamptz;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(711902,1);
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id AND user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('action','stop'); END IF;
  IF j.state IN ('completed','failed') THEN RETURN jsonb_build_object('action','stop'); END IF;
  IF j.state='dispatched' THEN RETURN jsonb_build_object('action','observe','claim',j.claim_token,'audit',j.audit_id,'dispatchedAt',j.dispatched_at); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.generations WHERE id=p_id AND user_id=j.user_id) THEN
    UPDATE private.image_jobs SET state='failed',finished_at=clock_timestamp() WHERE id=p_id;
    RETURN jsonb_build_object('action','stop');
  END IF;
  IF NOT private.image_job_authorized(j.user_id,j.session_id) THEN
    UPDATE private.image_jobs SET state='failed',finished_at=clock_timestamp() WHERE id=p_id;
    UPDATE public.generations SET status='failed',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('error','Queued generation cancelled because access was revoked.') WHERE id=p_id AND user_id=j.user_id;
    RETURN jsonb_build_object('action','stop');
  END IF;
  SELECT not_before INTO cooldown FROM private.image_provider_cooldown WHERE singleton;
  IF cooldown>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',greatest(1,ceil(extract(epoch FROM cooldown-clock_timestamp())))); END IF;
  IF j.not_before>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',greatest(1,ceil(extract(epoch FROM j.not_before-clock_timestamp())))); END IF;
  IF j.state='preparing' AND j.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',30); END IF;
  IF j.state='preparing' AND j.audit_id IS NOT NULL THEN PERFORM public.finish_openai_request(j.audit_id,'rejected'); END IF;
  SELECT count(*) INTO busy FROM private.image_jobs WHERE user_id=j.user_id AND id<>p_id
    AND ((state='preparing' AND lease_until>clock_timestamp()) OR (state='dispatched' AND dispatched_at>clock_timestamp()-interval '330 seconds'));
  SELECT count(*) INTO ahead FROM private.image_jobs WHERE user_id=j.user_id AND state='queued'
    AND not_before<=clock_timestamp() AND sequence<j.sequence;
  IF busy>=24 OR ahead>=24-busy THEN RETURN jsonb_build_object('action','wait','retryAfter',30); END IF;
  audit := gen_random_uuid();
  admission := public.start_openai_request(audit,j.user_id,j.session_id,'image',p_id);
  IF NOT (admission->>'allowed')::boolean THEN
    IF admission->>'reason'='duplicate' THEN
      UPDATE private.image_jobs SET state='dispatched',dispatched_at=clock_timestamp(),claim_token=p_claim WHERE id=p_id;
      RETURN jsonb_build_object('action','observe','claim',p_claim,'dispatchedAt',clock_timestamp());
    END IF;
    UPDATE private.image_jobs SET state='queued',not_before=clock_timestamp()+make_interval(secs=>coalesce((admission->>'retry_after')::integer,60)),lease_until=NULL WHERE id=p_id;
    RETURN jsonb_build_object('action','wait','retryAfter',coalesce((admission->>'retry_after')::integer,60));
  END IF;
  UPDATE private.image_jobs SET state='preparing',claim_token=p_claim,audit_id=audit,lease_until=clock_timestamp()+interval '120 seconds' WHERE id=p_id;
  RETURN jsonb_build_object('action','prepare','claim',p_claim,'audit',audit,'payload',j.payload);
END;
$$;

CREATE FUNCTION public.defer_rate_limited_image_job(p_id text,p_claim uuid,p_retry_after integer,p_request_id text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs; retry_at timestamptz;
BEGIN
  IF p_retry_after IS NULL OR p_retry_after<1 OR p_retry_after>86400 THEN RETURN false; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(711902,1);
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id FOR UPDATE;
  IF NOT FOUND OR j.state<>'dispatched' OR j.claim_token IS DISTINCT FROM p_claim OR j.audit_id IS NULL
    OR NOT EXISTS(SELECT 1 FROM private.openai_requests WHERE id=j.audit_id AND user_id=j.user_id AND generation_id=j.id AND outcome='accepted')
    THEN RETURN false; END IF;
  retry_at := clock_timestamp()+make_interval(secs=>p_retry_after);
  UPDATE private.openai_requests SET outcome='rejected',provider_status=429,provider_request_id=p_request_id,finished_at=clock_timestamp() WHERE id=j.audit_id;
  UPDATE private.image_provider_cooldown SET not_before=greatest(not_before,retry_at) WHERE singleton;
  UPDATE private.image_jobs SET state='queued',not_before=retry_at,dispatched_at=NULL,lease_until=NULL,claim_token=NULL,audit_id=NULL WHERE id=p_id;
  UPDATE public.generations SET status='pending',metadata=(coalesce(metadata,'{}'::jsonb)-'error')||
    jsonb_build_object('imageStage','queued','imageRateLimitRetryAt',floor(extract(epoch FROM retry_at)*1000)::bigint)
    WHERE id=p_id AND user_id=j.user_id AND status<>'completed';
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.defer_rate_limited_image_job(text,uuid,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.defer_rate_limited_image_job(text,uuid,integer,text) TO service_role;

ALTER TABLE private.image_provider_cooldown ADD COLUMN reason text NOT NULL DEFAULT 'rate' CHECK(reason IN ('rate','quota'));

CREATE FUNCTION public.defer_refused_image_job(p_id text,p_claim uuid,p_retry_after integer,p_request_id text,p_wait_reason text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE deferred boolean;
BEGIN
 IF p_wait_reason NOT IN ('rate','quota') OR p_wait_reason IS NULL OR (p_wait_reason='quota' AND p_retry_after<3600) THEN RETURN false; END IF;
 deferred:=public.defer_rate_limited_image_job(p_id,p_claim,p_retry_after,p_request_id);
 IF deferred THEN
  UPDATE private.image_provider_cooldown SET reason=p_wait_reason WHERE singleton;
  UPDATE public.generations g SET metadata=coalesce(g.metadata,'{}'::jsonb)||jsonb_build_object('imageQueueWaitReason',p_wait_reason)
   FROM private.image_jobs j WHERE g.id=j.id AND g.user_id=j.user_id AND j.state='queued';
 END IF;
 RETURN deferred;
END;
$$;
REVOKE ALL ON FUNCTION public.defer_refused_image_job(text,uuid,integer,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.defer_refused_image_job(text,uuid,integer,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_image_job(p_id text, p_user_id uuid, p_claim uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE j private.image_jobs; admission jsonb; audit uuid; busy integer; ahead integer; cooldown timestamptz; wait_reason text;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(711902,1);
  SELECT * INTO j FROM private.image_jobs WHERE id=p_id AND user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('action','stop'); END IF;
  IF j.state IN ('completed','failed') THEN RETURN jsonb_build_object('action','stop'); END IF;
  IF j.state='dispatched' THEN RETURN jsonb_build_object('action','observe','claim',j.claim_token,'audit',j.audit_id,'dispatchedAt',j.dispatched_at); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.generations WHERE id=p_id AND user_id=j.user_id) THEN
    UPDATE private.image_jobs SET state='failed',finished_at=clock_timestamp() WHERE id=p_id;
    RETURN jsonb_build_object('action','stop');
  END IF;
  IF NOT private.image_job_authorized(j.user_id,j.session_id) THEN
    UPDATE private.image_jobs SET state='failed',finished_at=clock_timestamp() WHERE id=p_id;
    UPDATE public.generations SET status='failed',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('error','Queued generation cancelled because access was revoked.') WHERE id=p_id AND user_id=j.user_id;
    RETURN jsonb_build_object('action','stop');
  END IF;
  SELECT not_before,reason INTO cooldown,wait_reason FROM private.image_provider_cooldown WHERE singleton;
  IF cooldown>clock_timestamp() THEN
    UPDATE public.generations SET metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('imageQueueWaitReason',wait_reason) WHERE id=p_id AND user_id=j.user_id AND status='pending';
    RETURN jsonb_build_object('action','wait','retryAfter',greatest(1,ceil(extract(epoch FROM cooldown-clock_timestamp()))));
  END IF;
  IF j.not_before>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',greatest(1,ceil(extract(epoch FROM j.not_before-clock_timestamp())))); END IF;
  IF j.state='preparing' AND j.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('action','wait','retryAfter',30); END IF;
  IF j.state='preparing' AND j.audit_id IS NOT NULL THEN PERFORM public.finish_openai_request(j.audit_id,'rejected'); END IF;
  SELECT count(*) INTO busy FROM private.image_jobs WHERE user_id=j.user_id AND id<>p_id
    AND ((state='preparing' AND lease_until>clock_timestamp()) OR (state='dispatched' AND dispatched_at>clock_timestamp()-interval '330 seconds'));
  SELECT count(*) INTO ahead FROM private.image_jobs WHERE user_id=j.user_id AND state='queued'
    AND not_before<=clock_timestamp() AND sequence<j.sequence;
  IF busy>=24 OR ahead>=24-busy THEN RETURN jsonb_build_object('action','wait','retryAfter',30); END IF;
  audit := gen_random_uuid();
  admission := public.start_openai_request(audit,j.user_id,j.session_id,'image',p_id);
  IF NOT (admission->>'allowed')::boolean THEN
    IF admission->>'reason'='duplicate' THEN
      UPDATE private.image_jobs SET state='dispatched',dispatched_at=clock_timestamp(),claim_token=p_claim WHERE id=p_id;
      RETURN jsonb_build_object('action','observe','claim',p_claim,'dispatchedAt',clock_timestamp());
    END IF;
    UPDATE private.image_jobs SET state='queued',not_before=clock_timestamp()+make_interval(secs=>coalesce((admission->>'retry_after')::integer,60)),lease_until=NULL WHERE id=p_id;
    RETURN jsonb_build_object('action','wait','retryAfter',coalesce((admission->>'retry_after')::integer,60));
  END IF;
  UPDATE private.image_jobs SET state='preparing',claim_token=p_claim,audit_id=audit,lease_until=clock_timestamp()+interval '120 seconds' WHERE id=p_id;
  RETURN jsonb_build_object('action','prepare','claim',p_claim,'audit',audit,'payload',j.payload);
END;
$$;

ALTER TABLE public.saved_people ADD COLUMN is_shared boolean NOT NULL DEFAULT false;
ALTER TABLE public.reference_images ADD COLUMN is_shared boolean NOT NULL DEFAULT false;
ALTER TABLE public.reference_images ADD CONSTRAINT shared_reference_snapshot
  CHECK (NOT is_shared OR data LIKE 'data:image/%;base64,%');
CREATE INDEX saved_people_shared_created ON public.saved_people(created_at DESC)
  WHERE is_shared AND deleted_at IS NULL;
CREATE INDEX reference_images_shared_created ON public.reference_images(created_at DESC) WHERE is_shared;
DROP POLICY owner_read ON public.saved_people;
CREATE POLICY owner_or_shared_read ON public.saved_people FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR (is_shared AND deleted_at IS NULL));
DROP POLICY owner_read ON public.reference_images;
CREATE POLICY owner_or_shared_read ON public.reference_images FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR is_shared OR (SELECT public.is_admin()));

ALTER TABLE public.folder_shares
  ADD COLUMN share_token text CHECK (share_token ~ '^[A-Za-z0-9_-]{43}$'),
  ADD COLUMN legacy_token_hash text UNIQUE CHECK (legacy_token_hash ~ '^[0-9a-f]{64}$');

CREATE OR REPLACE FUNCTION public.resolve_folder_share(p_token_hash text, p_offset integer DEFAULT 0, p_media_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH shared AS (
    SELECT f.id, f.name, f.user_id, s.expires_at
    FROM public.folder_shares s
    JOIN public.folders f ON f.id = s.folder_id AND f.user_id = s.user_id
    JOIN auth.users u ON u.id = s.user_id
    WHERE (s.token_hash = p_token_hash OR s.legacy_token_hash = p_token_hash) AND s.expires_at > now()
      AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous, false)
      AND EXISTS (SELECT 1 FROM public.authorized_emails a
        WHERE lower(btrim(a.email)) = lower(btrim(u.email)) AND a.is_active)
      AND p_offset BETWEEN 0 AND 1000000
  ), media AS (
    SELECT g.id, g.created_at, original.name AS storage_path, thumbnail.name AS thumbnail_path
    FROM shared s
    JOIN public.generations g ON g.folder_id = s.id AND g.user_id = s.user_id
    JOIN storage.objects original ON original.bucket_id = 'media'
      AND original.name = coalesce(nullif(g.storage_path, ''), g.id || '.png')
      AND (original.owner_id = s.user_id::text OR EXISTS (
        SELECT 1 FROM private.legacy_media_owners l WHERE l.name = original.name AND l.user_id = s.user_id)
        OR (original.owner_id IS NULL AND original.name IN (
          'openai/' || s.user_id::text || '/' || g.id || '.png',
          'openai/' || s.user_id::text || '/' || g.id || '.jpg',
          'openai/' || s.user_id::text || '/' || g.id || '.webp')
          AND EXISTS (SELECT 1 FROM private.openai_requests r
            WHERE r.user_id = s.user_id AND r.generation_id = g.id
              AND r.kind = 'image' AND r.outcome = 'completed')))
      AND original.metadata->>'mimetype' IN ('image/png', 'image/jpeg', 'image/webp', 'image/avif')
    LEFT JOIN storage.objects thumbnail ON thumbnail.bucket_id = 'media'
      AND thumbnail.name = coalesce(nullif(g.thumbnail_path, ''), g.id || '_thumb.png')
      AND (thumbnail.owner_id = s.user_id::text OR EXISTS (
        SELECT 1 FROM private.legacy_media_owners l WHERE l.name = thumbnail.name AND l.user_id = s.user_id))
      AND thumbnail.metadata->>'mimetype' IN ('image/png', 'image/jpeg', 'image/webp', 'image/avif')
    WHERE g.type = 'image' AND (g.status IS NULL OR g.status = 'completed')
      AND (p_media_id IS NULL OR g.id = p_media_id)
    ORDER BY g.created_at DESC, g.id DESC
    LIMIT 49 OFFSET p_offset
  )
  SELECT jsonb_build_object('name', s.name, 'expiresAt', s.expires_at, 'images', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', m.id, 'storagePath', m.storage_path,
      'thumbnailPath', m.thumbnail_path) ORDER BY m.created_at DESC, m.id DESC) FROM media m
  ), '[]'::jsonb)) FROM shared s;
$$;
REVOKE ALL ON FUNCTION public.resolve_folder_share(text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_folder_share(text, integer, text) TO service_role;

NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION private.can_access_media(object_name text, object_owner text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_authorized() AND (
    public.is_admin()
    OR coalesce(object_owner = (SELECT auth.uid())::text, false)
    OR EXISTS (SELECT 1 FROM private.legacy_media_owners l
      WHERE l.name = object_name AND l.user_id = (SELECT auth.uid()))
    OR (object_owner IS NULL AND EXISTS (
      SELECT 1 FROM private.openai_requests r
      WHERE r.user_id = (SELECT auth.uid()) AND r.kind = 'image' AND r.outcome = 'completed'
        AND r.generation_id = split_part(split_part(object_name, '/', 3), '.', 1)
        AND object_name IN (
          'openai/' || r.user_id::text || '/' || r.generation_id || '.png',
          'openai/' || r.user_id::text || '/' || r.generation_id || '.jpg',
          'openai/' || r.user_id::text || '/' || r.generation_id || '.webp')
    ))
  );
$$;
REVOKE ALL ON FUNCTION private.can_access_media(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_access_media(text,text) TO anon, authenticated;

UPDATE public.text_model_defaults SET model='anthropic/claude-opus-5.5',
  gemini_thinking='MEDIUM', openai_reasoning='medium', revision=revision+1,
  updated_by=NULL, updated_at=now()
WHERE singleton AND (model IS DISTINCT FROM 'anthropic/claude-opus-5.5'
  OR gemini_thinking IS DISTINCT FROM 'MEDIUM' OR openai_reasoning IS DISTINCT FROM 'medium');

NOTIFY pgrst, 'reload schema';
