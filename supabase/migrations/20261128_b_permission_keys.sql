-- B: allow the four permission keys the platform already uses in the UI and in C1/C2:
-- customers.contact, providers.contact, hr.view, hr.manage.
-- Existing 26 keys are kept exactly as they are. Existing rows are not touched.
BEGIN;

ALTER TABLE public.staff_permissions
  DROP CONSTRAINT IF EXISTS staff_permissions_allowed_keys;

ALTER TABLE public.staff_permissions
  ADD CONSTRAINT staff_permissions_allowed_keys CHECK (
    permissions <@ ARRAY[
      'dashboard.view', 'customers.view', 'customers.manage', 'customers.contact',
      'providers.view', 'providers.review', 'providers.contact',
      'requests.view', 'requests.manage',
      'services.view', 'services.manage',
      'categories.view', 'categories.manage',
      'messages.view',
      'payments.view', 'payments.manage',
      'reports.view',
      'ads.view', 'ads.manage',
      'settings.view', 'settings.manage',
      'support.view', 'support.manage',
      'wallet.view', 'wallet.manage', 'payouts.prepare',
      'loyalty.view', 'tiers.view',
      'hr.view', 'hr.manage'
    ]::text[]
  );


-- catalog: customers.contact exists but is marked admin/owner only and not delegable. Make it delegable to staff
-- (Ahmed's rule: staff with customers.contact see phone/address; admin and owner always).
UPDATE private.permission_catalog
SET description = 'التواصل مع العملاء: رؤية الهاتف والواتساب والعنوان',
    is_delegable = true
WHERE permission_key = 'customers.contact';

INSERT INTO private.permission_catalog
  (permission_key, module, action, description, sensitivity, is_delegable, is_legacy, is_active)
VALUES
  ('providers.contact', 'providers', 'contact', 'التواصل مع مزودي الخدمات: رؤية الهاتف والواتساب', 'critical', true, false, true),
  ('hr.view', 'hr', 'view', 'عرض الموارد البشرية', 'high', true, false, true),
  ('hr.manage', 'hr', 'manage', 'إدارة الموارد البشرية', 'critical', true, false, true)
ON CONFLICT (permission_key) DO NOTHING;

COMMIT;
