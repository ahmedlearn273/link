BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave2-k1-complaints',
'20261128_k1_complaints.sql sha256 fc57f8e0d41214e8211a57b10e2ac5a0d9bfd37d9add360d0fe1a722e89a6d17',
'k1 tests (rollback) sha256 87b88f5e671ffa4b32eb70aa9940a9428f5bc8b138eb38118f5306bcfa3dce97 passed after execution; counters unchanged; ratings, notifications, cron untouched; 3 tables RLS on, 9 public fns authenticated only',
'Ahmed approved wave 2 in order W1,K1,K3 (Telegram 30678188 "نفذ يلا"), relayed by Main.');
COMMIT;
