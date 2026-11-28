BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave2-h3-hr-suspend-staff',
'20261128_h3_hr_suspend_staff.sql sha256 ca5d08e5da00b317fb16f4d71b0c2bfa3762f2c32bd345932e90066d628dbce0',
'20261128_h3_tests_rollback.sql sha256 3918ab2281379e12d0ef6f644b7d4b8c85d8565e29b2487a00984f68c44ca359 passed after execution (ROLLBACK); counters unchanged; hr_* execute authenticated only; trigger prevent_profile_privilege_change updated (restore copy sha256 477fa1badf1d310c573180cf0736bed6779ee585f9535842f5416545f5b63ea0)',
'Ahmed approved H3/H4 (Telegram 30699026 "نفذ", reply to the presentation with sha ca5d08e5), relayed by Main.');
COMMIT;
