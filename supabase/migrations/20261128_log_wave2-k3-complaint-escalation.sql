BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave2-k3-complaint-escalation',
'20261128_k3_complaint_escalation.sql sha256 b152ab02ebeeadcceb9d4ed0a5c9eab9bf7b91faf6302147c8e3db31404ef56b',
'k3 tests (rollback) sha256 d6d0577b20e3bf5778ac211ce1029203f8d6c19bbae5e653a230b2cca1d49ecc passed after execution; settings enabled=false; no cron job, no notifications',
'Ahmed approved wave 2 in order W1,K1,K3 (Telegram 30678188 "نفذ يلا"), relayed by Main.');
COMMIT;
