BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave1-d2a-whatsapp',
'20261128_d2a_whatsapp_column_and_update.sql sha256 1d3014bbd89fe06d07ee9fced37030b7d4b91bd41d7d68a116e76a45fb1131e3',
'20261128_d2a_tests_rollback.sql sha256 d4b0e06a8ede837286da1c886f3fc408f54ab0f4aa76ef1cca9e0c2356f68302 passed (ROLLBACK); counters unchanged 15/17/5/2130/51',
'Ahmed approved wave 1 (Telegram 30551182), relayed by Main; rehearsal green first. whatsapp column + update_my_whatsapp; d2b parked.');
COMMIT;
