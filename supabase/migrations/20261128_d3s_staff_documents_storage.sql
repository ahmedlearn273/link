-- Run in the Supabase dashboard SQL editor (owner of storage.objects), NOT through the pooler as postgres.
-- Private bucket for staff documents + admin/owner-only policies. No anon access.
BEGIN;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('staff-documents', 'staff-documents', false, 10485760, ARRAY['application/pdf','image/jpeg','image/png'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 10485760,
  allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png'];

DROP POLICY IF EXISTS staff_documents_storage_select ON storage.objects;
CREATE POLICY staff_documents_storage_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'staff-documents' AND private.can_manage_staff_profile(((storage.foldername(name))[1])::uuid));
DROP POLICY IF EXISTS staff_documents_storage_insert ON storage.objects;
CREATE POLICY staff_documents_storage_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'staff-documents' AND private.can_manage_staff_profile(((storage.foldername(name))[1])::uuid));
DROP POLICY IF EXISTS staff_documents_storage_delete ON storage.objects;
CREATE POLICY staff_documents_storage_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'staff-documents' AND private.can_manage_staff_profile(((storage.foldername(name))[1])::uuid));
COMMIT;
