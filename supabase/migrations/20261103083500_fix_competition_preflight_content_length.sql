-- Storage preflight supplies contentLength; completed metadata uses size.
alter policy competition_evidence_upload on storage.objects to authenticated with check (
 bucket_id='school-competition-files'
 and split_part(name,'/',1)=(select auth.uid())::text
 and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|pdf)$'
 and exists(select 1 from public.profiles where id=(select auth.uid()))
 and (
  metadata is null or metadata='{}'::jsonb
  or (name like '%.jpg' and metadata->>'mimetype'='image/jpeg' and coalesce((metadata->>'size')::bigint,(metadata->>'contentLength')::bigint,0) between 0 and 3145728)
  or (name like '%.pdf' and metadata->>'mimetype'='application/pdf' and coalesce((metadata->>'size')::bigint,(metadata->>'contentLength')::bigint,0) between 0 and 8388608)
 )
);