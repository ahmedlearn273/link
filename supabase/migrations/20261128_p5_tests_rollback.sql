BEGIN;
DO $test$
DECLARE v_staff uuid; v_owner uuid; v_r jsonb; v_q text := 'الادوار الاساسيه ومسؤوليات كل دور وحدود الوصول';
BEGIN
  SELECT p.id INTO v_staff FROM public.profiles p WHERE p.role='staff' AND p.status='active' ORDER BY p.created_at LIMIT 1;
  SELECT p.id INTO v_owner FROM public.profiles p WHERE p.id::text LIKE '2213f856%';
  IF v_staff IS NULL OR v_owner IS NULL THEN RAISE EXCEPTION 'fixtures missing'; END IF;
  IF EXISTS (SELECT 1 FROM private.ai_knowledge_access WHERE role_name='staff' AND category IN ('roles','permissions') AND is_active) THEN RAISE EXCEPTION 'staff access still active'; END IF;
  IF (SELECT count(*) FROM private.ai_knowledge_access WHERE role_name IN ('admin','owner') AND category IN ('roles','permissions') AND is_active) <> 4 THEN RAISE EXCEPTION 'admin/owner access changed'; END IF;
  IF (SELECT count(*) FROM private.ai_knowledge_access WHERE is_active) <> 29 THEN RAISE EXCEPTION 'unexpected active row count'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_staff::text, true);
  v_r := public.prime_answer(v_q);
  IF v_r->>'answer' LIKE 'الأدوار والصلاحيات وحدود الوصول%' THEN RAISE EXCEPTION 'staff still reads roles doc'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_r := public.prime_answer(v_q);
  IF v_r->>'answer' NOT LIKE 'الأدوار والصلاحيات وحدود الوصول%' THEN RAISE EXCEPTION 'owner lost roles doc: %', left(v_r->>'answer',80); END IF;
  RAISE NOTICE 'P5 tests passed';
END;
$test$;
ROLLBACK;
