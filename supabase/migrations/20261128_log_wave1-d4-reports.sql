BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave1-d4-reports',
'20261128_d4_staff_reports.sql sha256 b50efc5ab20e8ad1fa97e8e1e8c30bb5cc040091acddcb3cfee99cce898c5186',
'20261128_d4_tests_rollback.sql sha256 2403e99e6267e35bfde26ad55312e809e4cf049765f8c97e9f7a30bac1ee7d44 passed (ROLLBACK); counters unchanged 15/17/5/2130/51',
'Ahmed approved wave 1 (Telegram 30551182), relayed by Main; rehearsal green first. staff_reports_summary.');
COMMIT;
