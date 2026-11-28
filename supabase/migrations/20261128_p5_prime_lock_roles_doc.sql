-- P5: the roles and permissions knowledge documents become visible to admin and owner only.
-- Data change only (2 rows in private.ai_knowledge_access): staff access is switched off, not deleted.
-- Rollback: UPDATE private.ai_knowledge_access SET is_active = true WHERE role_name = 'staff' AND category IN ('roles','permissions');
BEGIN;
UPDATE private.ai_knowledge_access
   SET is_active = false, updated_at = now()
 WHERE role_name = 'staff' AND category IN ('roles','permissions') AND is_active;
COMMIT;
