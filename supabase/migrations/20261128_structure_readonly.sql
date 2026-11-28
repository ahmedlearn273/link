SELECT column_name,data_type,is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' ORDER BY ordinal_position;
SELECT column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name IN ('id','role','status','suspension_reason','suspended_at','suspended_by','reactivated_at','staff_role_code','updated_at') ORDER BY 1;
SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname IN ('has_permission','is_active_admin','log_audit','write_audit','audit_row_change','admin_suspend_staff','admin_reactivate_staff','hr_suspend_staff');
SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('has_permission','is_active_admin');
SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin_reactivate_staff';
SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name ILIKE '%note%';
SELECT status, count(*) FROM public.profiles WHERE role='customer' GROUP BY 1;
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.profiles'::regclass AND contype='c';
