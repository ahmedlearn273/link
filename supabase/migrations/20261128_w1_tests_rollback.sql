-- W1 ROLLBACK tests. Run AFTER 20261128_w1_customer_wallet.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE
  v_cust uuid; v_staff uuid; v_ok boolean; v_res jsonb; v_bal numeric;
BEGIN
  IF has_function_privilege('anon','public.get_my_customer_wallet()','EXECUTE') THEN RAISE EXCEPTION 'anon can read wallet'; END IF;
  IF NOT has_function_privilege('authenticated','public.get_my_customer_wallet()','EXECUTE') THEN RAISE EXCEPTION 'authenticated cannot read wallet'; END IF;
  IF has_function_privilege('authenticated','private.credit_customer_wallet(uuid,numeric,text,text,uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','private.credit_customer_wallet(uuid,numeric,text,text,uuid,uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'credit function is exposed';
  END IF;
  IF has_table_privilege('authenticated','public.customer_wallets','SELECT') OR has_table_privilege('authenticated','public.customer_wallet_transactions','SELECT')
     OR has_table_privilege('anon','public.customer_wallets','SELECT') THEN RAISE EXCEPTION 'wallet tables not locked'; END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT id INTO v_cust FROM public.profiles WHERE role='customer' AND status='active' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_staff FROM public.profiles WHERE role='staff' AND status='active' ORDER BY created_at LIMIT 1;
  IF v_cust IS NULL OR v_staff IS NULL THEN RAISE EXCEPTION 'prerequisite missing'; END IF;

  -- empty wallet
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_res := public.get_my_customer_wallet();
  IF (v_res->>'balance')::numeric <> 0 OR v_res->>'currency' <> 'EGP' THEN RAISE EXCEPTION 'new wallet is not empty EGP'; END IF;

  -- credit twice as the platform
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM private.credit_customer_wallet(v_cust, 100, 'compensation', 'test', NULL, NULL, NULL);
  v_bal := private.credit_customer_wallet(v_cust, 50.5, 'compensation', 'test2', NULL, NULL, NULL);
  IF v_bal <> 150.5 THEN RAISE EXCEPTION 'balance wrong: %', v_bal; END IF;

  v_ok := false;
  BEGIN PERFORM private.credit_customer_wallet(v_cust, -5, 'compensation', 'x', NULL, NULL, NULL);
  EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'negative credit accepted'; END IF;
  v_ok := false;
  BEGIN PERFORM private.credit_customer_wallet(v_staff, 5, 'compensation', 'x', NULL, NULL, NULL);
  EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'credit to a non customer accepted'; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_res := public.get_my_customer_wallet();
  IF (v_res->>'balance')::numeric <> 150.5 OR jsonb_array_length(v_res->'transactions') <> 2 THEN RAISE EXCEPTION 'wallet read wrong'; END IF;
  IF v_res->'transactions'->0 ? 'created_by' THEN RAISE EXCEPTION 'wallet leaks staff identity'; END IF;

  -- staff cannot read a customer wallet through the customer function
  PERFORM set_config('request.jwt.claim.sub', v_staff::text, true);
  v_ok := false;
  BEGIN PERFORM public.get_my_customer_wallet(); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'non customer read a wallet'; END IF;

  RAISE NOTICE 'W1 tests passed';
END;
$test$;
ROLLBACK;
