-- K3: complaint auto-escalation (structure only). Requires K1.
-- Times decided by Ahmed: 2 hours to operations manager (level 1), 8 hours to general manager (level 2),
-- both counted from the moment the complaint was filed.
-- NOT ACTIVE: settings.enabled is false, no cron job is created, no notification is sent.
-- Activation (enabled=true + a cron job) is a separate approved step.
BEGIN;

CREATE TABLE IF NOT EXISTS public.complaint_escalation_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT false,
  ops_after_minutes integer NOT NULL DEFAULT 120 CHECK (ops_after_minutes BETWEEN 10 AND 10080),
  gm_after_minutes integer NOT NULL DEFAULT 480 CHECK (gm_after_minutes BETWEEN 10 AND 10080),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (gm_after_minutes > ops_after_minutes)
);
INSERT INTO public.complaint_escalation_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.complaint_escalation_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.complaint_escalation_settings FROM PUBLIC, anon, authenticated;

-- Returns how many complaints were moved up one level. Does nothing while disabled.
CREATE OR REPLACE FUNCTION private.escalate_overdue_complaints()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_set public.complaint_escalation_settings%ROWTYPE;
  v_n integer := 0;
  v_rows integer;
  r record;
BEGIN
  SELECT * INTO v_set FROM public.complaint_escalation_settings WHERE id;
  IF NOT FOUND OR NOT v_set.enabled THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT c.id, c.escalation_level
    FROM public.complaints c
    WHERE c.status IN ('open','in_review','escalated')
      AND ((c.escalation_level = 0 AND c.created_at <= now() - make_interval(mins => v_set.ops_after_minutes))
        OR (c.escalation_level = 1 AND c.created_at <= now() - make_interval(mins => v_set.gm_after_minutes)))
    ORDER BY c.created_at
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.complaints
    SET escalation_level = r.escalation_level + 1, status = 'escalated', escalated_at = now(), updated_at = now()
    WHERE id = r.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 1 THEN
      INSERT INTO public.complaint_events (complaint_id, actor_id, event_type, meta)
      VALUES (r.id, NULL, 'escalated',
        jsonb_build_object('level', r.escalation_level + 1,
          'to', CASE WHEN r.escalation_level = 0 THEN 'operations_manager' ELSE 'general_manager' END));
      v_n := v_n + 1;
    END IF;
  END LOOP;

  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION private.escalate_overdue_complaints() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
