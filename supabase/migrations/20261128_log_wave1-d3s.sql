BEGIN;
INSERT INTO private.executed_sql_log (stage, sql_text, verification, notes) VALUES (
'wave1-d3s-staff-documents-storage',
'20261128_d3s_staff_documents_storage.sql sha256 61c3f08917ade768a58dbd39a367d701d8ef5361519826348e3adbc38d9f95ec',
'rehearsal BEGIN..ROLLBACK passed first; bucket staff-documents private 10MB pdf/jpg/png and 3 policies verified; counters unchanged 15/17/5/2137/51',
'Ahmed approved d3s explicitly (Telegram 30608689), relayed by Main; run via pooler as postgres.');
COMMIT;
