-- E: staff_reports_summary(p_from, p_to). Aggregates only: no phones, no names.
BEGIN;
CREATE OR REPLACE FUNCTION public.staff_reports_summary(p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_admin boolean;
  v_fin boolean;
  v_from timestamptz;
  v_to timestamptz;
  v_by_status jsonb; v_by_service jsonb; v_by_city jsonb; v_by_day jsonb; v_reviews jsonb; v_fin_json jsonb := NULL;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  v_admin := private.is_active_admin();
  IF NOT (v_admin OR (private.has_permission('reports.view') AND EXISTS (
        SELECT 1 FROM public.profiles p WHERE p.id = v_uid AND p.role = 'staff' AND p.status = 'active'))) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR (p_to - p_from) > 366 THEN
    RAISE EXCEPTION 'Invalid date range (maximum 366 days)' USING ERRCODE = '22023';
  END IF;
  v_from := p_from::timestamptz;
  v_to := (p_to + 1)::timestamptz;
  v_fin := v_admin OR private.has_permission('payments.view');

  SELECT coalesce(jsonb_object_agg(status, n), '{}'::jsonb) INTO v_by_status
  FROM (SELECT sr.status, count(*) n FROM public.service_requests sr WHERE sr.created_at >= v_from AND sr.created_at < v_to GROUP BY 1) t;

  SELECT coalesce(jsonb_agg(jsonb_build_object('service', name_ar, 'count', n) ORDER BY n DESC), '[]'::jsonb) INTO v_by_service
  FROM (SELECT coalesce(s.name_ar,'-') name_ar, count(*) n FROM public.service_requests sr LEFT JOIN public.services s ON s.id = sr.service_id
        WHERE sr.created_at >= v_from AND sr.created_at < v_to GROUP BY 1) t;

  SELECT coalesce(jsonb_agg(jsonb_build_object('city', city, 'count', n) ORDER BY n DESC), '[]'::jsonb) INTO v_by_city
  FROM (SELECT coalesce(nullif(sr.city,''),'-') city, count(*) n FROM public.service_requests sr
        WHERE sr.created_at >= v_from AND sr.created_at < v_to GROUP BY 1) t;

  SELECT coalesce(jsonb_agg(jsonb_build_object('day', d, 'count', n) ORDER BY d), '[]'::jsonb) INTO v_by_day
  FROM (SELECT (sr.created_at AT TIME ZONE 'Africa/Cairo')::date d, count(*) n FROM public.service_requests sr
        WHERE sr.created_at >= v_from AND sr.created_at < v_to GROUP BY 1) t;

  SELECT jsonb_build_object('count', count(*), 'average', round(avg(r.rating)::numeric, 2)) INTO v_reviews
  FROM public.reviews r WHERE r.created_at >= v_from AND r.created_at < v_to;

  IF v_fin THEN
    SELECT jsonb_build_object(
      'currency', 'EGP',
      'paid_count', count(*) FILTER (WHERE pay.payment_status = 'paid'),
      'pending_count', count(*) FILTER (WHERE pay.payment_status = 'pending'),
      'revenue', coalesce(sum(pay.amount) FILTER (WHERE pay.payment_status = 'paid'), 0),
      'commission', coalesce(sum(pay.commission_amount) FILTER (WHERE pay.payment_status = 'paid'), 0),
      'cash_paid', coalesce(sum(pay.amount) FILTER (WHERE pay.payment_status = 'paid' AND pay.payment_method = 'cash'), 0)
    ) INTO v_fin_json
    FROM public.payments pay WHERE pay.created_at >= v_from AND pay.created_at < v_to;
  END IF;

  RETURN jsonb_build_object('from', p_from, 'to', p_to, 'requests_by_status', v_by_status,
    'requests_by_service', v_by_service, 'requests_by_city', v_by_city, 'requests_by_day', v_by_day,
    'reviews', v_reviews, 'financial', v_fin_json);
END;
$function$;
REVOKE ALL ON FUNCTION public.staff_reports_summary(date, date) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.staff_reports_summary(date, date) TO authenticated;
COMMIT;
