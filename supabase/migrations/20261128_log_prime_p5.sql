BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'prime-p5-lock-roles-doc',
'20261128_p5_prime_lock_roles_doc.sql sha256 7ddec53efd64dc4b69551e7ffced3c54210c12e5b55c379fc51405447c6d64ec',
'20261128_p5_tests_rollback.sql sha256 3c5efad4b8ed263725a7603d9aa5ef05952cbcc785e604aab38211faa87010f9 passed after execution (ROLLBACK); P3 and P1b tests passed again; counters unchanged; staff access inactive on roles and permissions, admin and owner active',
'Executed on the Telegram reply "نفذ اقتراحك" (message 30810422, to the message presenting sha 7ddec53e), relayed by Main.');
COMMIT;
