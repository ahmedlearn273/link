BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave1-d2b-whatsapp-enforcement',
'20261128_d2b_whatsapp_signup_enforcement.sql sha256 0413b39be7b58714b172907097366418214c0959054e50767af947bc9da9b32e',
'20261128_d2b_tests_rollback.sql sha256 2c4d58434a8a5e7e6cdf600ce25a4d3b4afa840fb42fb0a3f9da8d499844ce3e passed (ROLLBACK): valid +201 stored, missing and malformed rejected (22023), staff exempt; counters unchanged 15/17/5/2137/51; no leftover test users',
'Ahmed approved d2b (Telegram 30651056), relayed by Main; signup UI with whatsapp_number already live in production (main aff8982).');
COMMIT;
