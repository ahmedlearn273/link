BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave1-d3-staff-docs-suspension',
'20261128_d3_staff_documents_and_suspension.sql sha256 ac23d0c12cfdabd744eebf79b5048234c60d30d57a861393258d04aee5a4d788',
'20261128_d3_tests_rollback.sql sha256 144d1878de6f1c7e1cea2234a1a2d23b2fae5583aab705ce6c2bf3c418ab7139 passed (ROLLBACK); counters unchanged 15/17/5/2130/51',
'Ahmed approved wave 1 (Telegram 30551182), relayed by Main; rehearsal green first. staff_documents table + admin_suspend/reactivate_staff; storage bucket is a separate dashboard step.');
COMMIT;
