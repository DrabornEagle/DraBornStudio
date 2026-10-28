-- Run in YOUR Supabase SQL editor after signing in once. Replace only this
-- example address. Registration alone never creates an administrator.
DO $$
DECLARE owner_email text := 'replace-me@example.invalid'; owner_id uuid;
BEGIN
 IF owner_email LIKE '%@example.invalid' OR owner_email<>lower(btrim(owner_email)) THEN
  RAISE EXCEPTION 'Set your verified, lowercase owner email before running this script';
 END IF;
 SELECT id INTO STRICT owner_id FROM auth.users
 WHERE lower(btrim(email))=owner_email AND email_confirmed_at IS NOT NULL AND NOT coalesce(is_anonymous,false);
 INSERT INTO public.authorized_emails(email,is_active) VALUES(owner_email,true)
 ON CONFLICT(email) DO UPDATE SET is_active=true;
 UPDATE public.profiles SET role='admin' WHERE id=owner_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'The verified account profile does not exist';END IF;
END;
$$;
