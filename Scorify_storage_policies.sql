-- Run in Supabase SQL editor

-- Bucket for profile pictures (public read)
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true);

-- Bucket for submission files (private — served via signed URLs)
INSERT INTO storage.buckets (id, name, public)
VALUES ('submission-files', 'submission-files', false);

-- Policy: users can only upload to their own folder in avatars
CREATE POLICY "Avatar upload: own folder only"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'avatars'
  AND auth.uid()::text = (string_to_array(name, '/'))[1]
);

-- Policy: public read on avatars
CREATE POLICY "Avatar read: public"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- Policy: users can upload their own submission files
CREATE POLICY "Submission files: own folder only"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'submission-files'
  AND auth.uid()::text = (string_to_array(name, '/'))[1]
);

-- Policy: users can only read their own submission files
CREATE POLICY "Submission files: own read only"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'submission-files'
  AND auth.uid()::text = (string_to_array(name, '/'))[1]
);