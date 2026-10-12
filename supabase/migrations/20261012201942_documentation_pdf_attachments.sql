alter table public.documentations add column attachment_files jsonb not null default '[]' check(jsonb_typeof(attachment_files)='array' and jsonb_array_length(attachment_files)<=5);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('school-report-files','school-report-files',false,8388608,array['application/pdf']);
create policy report_files_upload on storage.objects for insert to authenticated with check(bucket_id='school-report-files' and split_part(name,'/',1)=(select auth.uid())::text and name~'^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-f0-9-]{36}\.pdf$' and exists(select 1 from public.profiles where id=(select auth.uid())));
create policy report_files_read on storage.objects for select to authenticated using(bucket_id='school-report-files' and exists(select 1 from public.documentations d where d.attachment_files @> jsonb_build_array(jsonb_build_object('bucket','school-report-files','path',name))));
create function documentation_private.validate_attachments() returns trigger language plpgsql security definer set search_path='' as $$
declare f jsonb;
begin
 if jsonb_array_length(new.attachment_files)>5 then raise exception 'يمكن إرفاق خمسة ملفات PDF كحد أقصى.';end if;
 for f in select * from jsonb_array_elements(new.attachment_files) loop
  if f->>'bucket' is distinct from 'school-report-files' or split_part(f->>'path','/',1) is distinct from new.created_by::text or split_part(f->>'path','/',2) is distinct from new.request_id::text or length(coalesce(f->>'name','')) not between 1 and 250 or not exists(select 1 from storage.objects o where o.bucket_id='school-report-files' and o.name=f->>'path' and coalesce((o.metadata->>'size')::bigint,0) between 1 and 8388608) then raise exception 'مرفق التقرير غير صالح أو لا يخص هذه المحاولة.';end if;
 end loop;return new;
end $$;
revoke all on function documentation_private.validate_attachments() from public,anon,authenticated;
create trigger documentation_attachment_check before insert on public.documentations for each row execute function documentation_private.validate_attachments();
