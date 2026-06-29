
CREATE OR REPLACE FUNCTION public.can_access_case_doc_path(_path text, _user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  parts text[];
  v_owner uuid;
  v_second text;
  v_case uuid;
  v_task uuid;
BEGIN
  IF _user_id IS NULL OR _path IS NULL THEN
    RETURN false;
  END IF;

  parts := storage.foldername(_path);
  IF array_length(parts, 1) IS NULL OR array_length(parts, 1) < 1 THEN
    RETURN false;
  END IF;

  BEGIN
    v_owner := parts[1]::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  IF v_owner = _user_id THEN
    RETURN true;
  END IF;

  v_second := parts[2];
  IF v_second IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (SELECT 1 FROM public.employees WHERE user_id = _user_id AND owner_id = v_owner) THEN
    IF v_second = 'chat' THEN
      RETURN true;
    END IF;
    IF v_second = 'tasks' THEN
      BEGIN
        v_task := parts[3]::uuid;
      EXCEPTION WHEN others THEN
        RETURN false;
      END;
      RETURN EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = v_task AND t.owner_id = v_owner);
    END IF;
    BEGIN
      v_case := v_second::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
    RETURN public.employee_can_access_case(v_case, _user_id);
  END IF;

  BEGIN
    v_case := v_second::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;
  RETURN EXISTS (
    SELECT 1
    FROM public.cases c
    JOIN public.clients cl ON cl.id = c.client_id
    WHERE c.id = v_case
      AND c.owner_id = v_owner
      AND cl.portal_user_id = _user_id
  );
END;
$$;
