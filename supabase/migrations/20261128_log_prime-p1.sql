BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'prime-p1-rule-engine',
'20261128_p1_prime_engine.sql sha256 15bb7dc5abeed4e0ec4ac46d9b2ad9ed69c2bfbbdb08b14b30872d6092b74098',
'20261128_p3_prime_tests_rollback.sql sha256 dcec5332fd27c6fe111f2d55159c2415d5c3f4908b67f5648baf798f301eafba passed after execution (ROLLBACK); counters unchanged; prime_answer authenticated only; private tables not exposed; per-role filtering tests passed',
'Ahmed approved P1 (Telegram 30733361 "نفذ", reply to the presentation with sha 15bb7dc5), relayed by Main.');
COMMIT;
