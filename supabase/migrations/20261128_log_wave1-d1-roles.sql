BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave1-d1-roles',
'20261128_d1_roles_and_contact_assign.sql sha256 f79b103b1dc203fd3f76a4ca1bed431431905467a9ba41201c1c3c423a7fbd59',
'20261128_d1_roles_tests_rollback.sql sha256 de567c667603ca3eac7ee475daa5f4f1efac4d325c39ae7809a378e86d26a8b9 passed (ROLLBACK); counters unchanged 15/17/5/2130/51',
'Ahmed approved wave 1 (Telegram 30551182), relayed by Main; rehearsal green first. GM/HR codes; customers.contact assignable.');
COMMIT;
