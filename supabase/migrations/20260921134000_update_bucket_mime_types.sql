-- Add docx and csv to the allowed_mime_types of the documents bucket
update storage.buckets
set allowed_mime_types = array[
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'text/plain',
  'text/csv',
  'text/markdown',
  'image/png',
  'image/jpeg'
]
where id = 'documents';
