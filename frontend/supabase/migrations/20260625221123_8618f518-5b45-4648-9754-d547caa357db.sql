CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_account_type text DEFAULT NULL, _access_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  user_email text;
  acct text := lower(coalesce(_account_type, ''));
  code text := nullif(trim(coalesce(_access_code, '')), '');
  linked_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT email INTO user_email FROM auth.users WHERE id = uid;

  IF acct NOT IN ('client', 'employee') THEN
    SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1;
    IF linked_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
      DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
      RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
    END IF;
    SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1;
    IF linked_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
      DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
      RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked_id);
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'lawyer') ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('linked', true, 'role', 'lawyer');
  END IF;

  IF acct = 'client' THEN
    UPDATE public.clients c
    SET portal_user_id = uid
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING c.id INTO linked_id;

    IF linked_id IS NULL THEN
      SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1;
    END IF;
    IF linked_id IS NULL THEN
      RETURN jsonb_build_object('linked', false, 'role', 'client', 'reason', 'client_not_found');
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
  END IF;

  IF acct = 'employee' THEN
    UPDATE public.employees e
    SET user_id = uid
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING e.id INTO linked_id;

    IF linked_id IS NULL THEN
      SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1;
    END IF;
    IF linked_id IS NULL THEN
      RETURN jsonb_build_object('linked', false, 'role', 'employee', 'reason', 'employee_not_found');
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked_id);
  END IF;

  RETURN jsonb_build_object('linked', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  acct text := lower(coalesce(NEW.raw_user_meta_data->>'account_type', 'lawyer'));
  code text := nullif(trim(coalesce(NEW.raw_user_meta_data->>'portal_access_code', '')), '');
  linked_id uuid;
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, email = EXCLUDED.email;

  IF acct = 'client' THEN
    UPDATE public.clients c
    SET portal_user_id = NEW.id
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING c.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'client') ON CONFLICT DO NOTHING;
  ELSIF acct = 'employee' THEN
    UPDATE public.employees e
    SET user_id = NEW.id
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING e.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'employee') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer') ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO service_role;