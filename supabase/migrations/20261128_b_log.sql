BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes)
VALUES (
 'B',
 'supabase/migrations/20261128_b_permission_keys.sql sha256 17d6eafc190e60aaea7e53fa3e2000ce6687ec6aad34e2c529965be19fa5facb: staff_permissions_allowed_keys extended to 30 keys; catalog customers.contact delegable; providers.contact, hr.view, hr.manage added',
 'CHECK shows 30 keys; catalog rows verified active and delegable; C1 Part 4 then passed',
 'Ahmed approved (Telegram 30497412); Main asked to log B.'
);
COMMIT;
