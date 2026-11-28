-- W1: client wallet (credit side only). Used first for complaint compensation.
-- Tables are locked: access only through functions. Spending the balance at checkout is NOT part of this file.
BEGIN;

CREATE TABLE IF NOT EXISTS public.customer_wallets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  balance numeric(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_wallet_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL CHECK (amount <> 0),
  kind text NOT NULL CHECK (kind IN ('compensation','spend','refund','adjustment')),
  note text CHECK (note IS NULL OR length(note) <= 500),
  complaint_id uuid,
  request_id uuid,
  created_by uuid REFERENCES public.profiles(id),
  balance_after numeric(12,2) NOT NULL CHECK (balance_after >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS customer_wallet_tx_customer_idx
  ON public.customer_wallet_transactions (customer_id, created_at DESC);

ALTER TABLE public.customer_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_wallet_transactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.customer_wallets FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.customer_wallet_transactions FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS audit_row_change ON public.customer_wallets;
CREATE TRIGGER audit_row_change AFTER INSERT OR UPDATE OR DELETE ON public.customer_wallets
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
DROP TRIGGER IF EXISTS audit_row_change ON public.customer_wallet_transactions;
CREATE TRIGGER audit_row_change AFTER INSERT OR UPDATE OR DELETE ON public.customer_wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

-- Internal credit. Not callable by any API role. Used by other SECURITY DEFINER functions.
CREATE OR REPLACE FUNCTION private.credit_customer_wallet(
  p_customer_id uuid, p_amount numeric, p_kind text, p_note text,
  p_complaint_id uuid, p_request_id uuid, p_actor uuid
) RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_new numeric(12,2);
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Credit amount must be positive' USING ERRCODE = '22023';
  END IF;
  IF p_kind NOT IN ('compensation','refund','adjustment') THEN
    RAISE EXCEPTION 'Invalid credit kind' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_customer_id AND role = 'customer') THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.customer_wallets (customer_id, balance)
  VALUES (p_customer_id, 0)
  ON CONFLICT (customer_id) DO NOTHING;

  UPDATE public.customer_wallets
  SET balance = balance + p_amount, updated_at = now()
  WHERE customer_id = p_customer_id
  RETURNING balance INTO v_new;

  INSERT INTO public.customer_wallet_transactions
    (customer_id, amount, kind, note, complaint_id, request_id, created_by, balance_after)
  VALUES (p_customer_id, p_amount, p_kind, left(p_note, 500), p_complaint_id, p_request_id, p_actor, v_new);

  RETURN v_new;
END;
$function$;

REVOKE ALL ON FUNCTION private.credit_customer_wallet(uuid,numeric,text,text,uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- The customer sees only their own balance and movements (no funding source, no staff identity).
CREATE OR REPLACE FUNCTION public.get_my_customer_wallet()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_bal numeric := 0;
  v_tx jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'customer' AND status = 'active') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT coalesce((SELECT w.balance FROM public.customer_wallets w WHERE w.customer_id = v_uid), 0) INTO v_bal;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'amount', t.amount, 'kind', t.kind, 'note', t.note,
           'balance_after', t.balance_after, 'created_at', t.created_at
         ) ORDER BY t.created_at DESC), '[]'::jsonb)
  INTO v_tx
  FROM (SELECT * FROM public.customer_wallet_transactions
        WHERE customer_id = v_uid ORDER BY created_at DESC LIMIT 50) t;

  RETURN jsonb_build_object('currency', 'EGP', 'balance', v_bal, 'transactions', v_tx);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_customer_wallet() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_customer_wallet() TO authenticated;

COMMIT;
