BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes)
VALUES (
 'C1',
 'staff_list_customers / staff_get_customer (created by shosho); verified by 20261128_c1_part4_rollback_test.sql sha256 d8642cd08e58d443d8ff72a0deed8f828a5ba0e27d1d1572e860057cb8ec9a2c, run after stage B 20261128_b_permission_keys.sql sha256 17d6eafc190e60aaea7e53fa3e2000ce6687ec6aad34e2c529965be19fa5facb',
 'C1 TESTS PASSED: test_role=ASV, list_count=4, phone_search_count=0; counters before=after 15/17/5/2130/51; ROLLBACK',
 'Ahmed approved B (Telegram 30497412) and Part 4 (30488838). Suspended-customer branch not tested (no suspended customer).'
);
COMMIT;
