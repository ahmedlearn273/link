-- K3 ROLLBACK tests. Run AFTER K1 and 20261128_k3_complaint_escalation.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE
  v_req uuid; v_cust uuid; v_c uuid; v_n integer; v_notif bigint; v_cron bigint;
BEGIN
  IF has_function_privilege('authenticated','private.escalate_overdue_complaints()','EXECUTE')
     OR has_function_privilege('anon','private.escalate_overdue_complaints()','EXECUTE') THEN RAISE EXCEPTION 'escalation function exposed'; END IF;
  IF has_table_privilege('authenticated','public.complaint_escalation_settings','SELECT') THEN RAISE EXCEPTION 'settings not locked'; END IF;
  IF (SELECT enabled FROM public.complaint_escalation_settings) THEN RAISE EXCEPTION 'escalation must start disabled'; END IF;
  IF (SELECT ops_after_minutes FROM public.complaint_escalation_settings) <> 120 OR (SELECT gm_after_minutes FROM public.complaint_escalation_settings) <> 480 THEN
    RAISE EXCEPTION 'default times are not 2h / 8h';
  END IF;
  SELECT count(*) INTO v_notif FROM public.notifications;
  SELECT count(*) INTO v_cron FROM cron.job;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT sr.id, sr.customer_id INTO v_req, v_cust FROM public.service_requests sr
   WHERE sr.status='completed' AND sr.provider_id IS NOT NULL ORDER BY sr.created_at LIMIT 1;
  IF v_req IS NULL THEN RAISE EXCEPTION 'prerequisite missing'; END IF;
  INSERT INTO public.complaints (request_id, customer_id, provider_id, category, description)
    SELECT v_req, v_cust, provider_id, 'other', 'escalation test complaint description' FROM public.service_requests WHERE id = v_req
    RETURNING id INTO v_c;

  -- disabled: nothing happens even when overdue
  UPDATE public.complaints SET created_at = now() - interval '10 hours' WHERE id = v_c;
  IF private.escalate_overdue_complaints() <> 0 THEN RAISE EXCEPTION 'escalated while disabled'; END IF;
  IF (SELECT escalation_level FROM public.complaints WHERE id = v_c) <> 0 THEN RAISE EXCEPTION 'level changed while disabled'; END IF;

  UPDATE public.complaint_escalation_settings SET enabled = true;
  -- 1h old: not yet
  UPDATE public.complaints SET created_at = now() - interval '1 hour' WHERE id = v_c;
  IF private.escalate_overdue_complaints() <> 0 THEN RAISE EXCEPTION 'escalated too early'; END IF;
  -- 3h old: operations manager
  UPDATE public.complaints SET created_at = now() - interval '3 hours' WHERE id = v_c;
  IF private.escalate_overdue_complaints() <> 1 THEN RAISE EXCEPTION 'level 1 not applied'; END IF;
  IF (SELECT escalation_level FROM public.complaints WHERE id = v_c) <> 1 OR (SELECT status FROM public.complaints WHERE id = v_c) <> 'escalated' THEN RAISE EXCEPTION 'level 1 state wrong'; END IF;
  IF private.escalate_overdue_complaints() <> 0 THEN RAISE EXCEPTION 'level 1 repeated'; END IF;
  -- 9h old: general manager
  UPDATE public.complaints SET created_at = now() - interval '9 hours' WHERE id = v_c;
  IF private.escalate_overdue_complaints() <> 1 THEN RAISE EXCEPTION 'level 2 not applied'; END IF;
  IF (SELECT escalation_level FROM public.complaints WHERE id = v_c) <> 2 THEN RAISE EXCEPTION 'level 2 state wrong'; END IF;
  IF private.escalate_overdue_complaints() <> 0 THEN RAISE EXCEPTION 'level 2 repeated'; END IF;
  IF (SELECT count(*) FROM public.complaint_events WHERE complaint_id = v_c AND event_type = 'escalated') <> 2 THEN RAISE EXCEPTION 'escalation events missing'; END IF;

  -- resolved complaints are not touched
  UPDATE public.complaints SET status = 'resolved', escalation_level = 0, resolution_note = 'closed already', resolved_at = now() WHERE id = v_c;
  IF private.escalate_overdue_complaints() <> 0 THEN RAISE EXCEPTION 'resolved complaint escalated'; END IF;

  IF (SELECT count(*) FROM public.notifications) <> v_notif THEN RAISE EXCEPTION 'notifications created'; END IF;
  IF (SELECT count(*) FROM cron.job) <> v_cron THEN RAISE EXCEPTION 'cron job created'; END IF;
  RAISE NOTICE 'K3 tests passed';
END;
$test$;
ROLLBACK;
