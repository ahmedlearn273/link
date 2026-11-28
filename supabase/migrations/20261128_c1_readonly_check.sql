SELECT 1 AS connected, current_user, now();
SELECT 'profiles' AS table_name, count(*)::bigint AS row_count FROM public.profiles
UNION ALL SELECT 'service_requests', count(*) FROM public.service_requests
UNION ALL SELECT 'staff_permissions', count(*) FROM public.staff_permissions
UNION ALL SELECT 'audit_logs', count(*) FROM public.audit_logs
UNION ALL SELECT 'staff_permission_grants', count(*) FROM private.staff_permission_grants;
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prosecdef AS security_definer,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
  has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('staff_list_customers','staff_get_customer');
SELECT stage, executed_at FROM private.executed_sql_log WHERE stage ILIKE '%C1%' ORDER BY executed_at DESC LIMIT 5;
