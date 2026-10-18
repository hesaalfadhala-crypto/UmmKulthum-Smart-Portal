-- Scope: competitions only. Existing documentation/profile policies and real records are untouched.
-- Preflight: SELECT/INSERT are explicitly retained; deletion is a marker, never a row/file DELETE.
-- Private competition evidence, atomic rosters and owner edits. No existing rows are removed.
create schema if not exists competition_private;
revoke all on schema competition_private from public,anon;
grant usage on schema competition_private to authenticated;
alter table public.competitions add column if not exists request_id uuid;
alter table public.competitions add column if not exists version integer not null default 0;
alter table public.competitions add column if not exists details jsonb not null default '{}';
alter table public.competitions add column if not exists deleted_at timestamptz;
create unique index if not exists competitions_request_key on public.competitions(created_by,request_id) where request_id is not null;
create table competition_private.revisions(id bigint generated always as identity primary key,competition_id bigint not null,changed_at timestamptz not null default now(),changed_by uuid,previous jsonb not null);
alter table competition_private.revisions enable row level security;
revoke all on competition_private.revisions from public,anon,authenticated;
create or replace function competition_private.guard_record() returns trigger language plpgsql security definer set search_path='' as $$
declare s jsonb; f jsonb; seen text[]:='{}'; k text; n int:=0; photos int:=0; pdfs int:=0;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Authentication required'; end if;
 if tg_op='INSERT' then
  if new.created_by is distinct from auth.uid() or new.deleted_at is not null then raise exception 'Invalid owner'; end if;
  new.version:=1; new.created_at:=now();
 else
  if new.id<>old.id or new.created_by is distinct from old.created_by or new.request_id is distinct from old.request_id or new.created_at is distinct from old.created_at or new.deleted_at is distinct from old.deleted_at then raise exception 'Protected competition fields'; end if;
  if new.version<>old.version+1 then raise exception 'Competition changed. Reload before saving'; end if;
  insert into competition_private.revisions(competition_id,changed_by,previous) values(old.id,auth.uid(),to_jsonb(old));
 end if;
 if length(trim(coalesce(new.competition_name,''))) not between 1 and 300 or coalesce(new.competition_type,'') not in ('داخلية','خارجية') or coalesce(trim(new.department),'')='' or coalesce(trim(new.supervisor),'')='' then raise exception 'Incomplete competition'; end if;
 if jsonb_typeof(new.students) is distinct from 'array' or jsonb_array_length(new.students)>10000 then raise exception 'Invalid student list'; end if;
 for s in select value from jsonb_array_elements(new.students) loop
  if jsonb_typeof(s)<>'object' or length(trim(coalesce(s->>'name',''))) not between 1 and 200 or length(trim(coalesce(s->>'class',''))) not between 1 and 120 or length(coalesce(s->>'section',''))>60 or length(coalesce(s->>'place',''))>200 then raise exception 'Invalid student row'; end if;
  k:=lower(regexp_replace(translate(coalesce(s->>'name','')||'|'||coalesce(s->>'class','')||'|'||coalesce(s->>'section',''),'أإآٱ٠١٢٣٤٥٦٧٨٩','اااا0123456789'),'[[:space:]ـًٌٍَُِّْٰ]+','','g'));
  if k=any(seen) then raise exception 'Duplicate student'; end if;seen:=array_append(seen,k); n:=n+1;
 end loop;
 new.student_count:=n;
 if jsonb_typeof(new.attachments) is distinct from 'array' or jsonb_array_length(new.attachments)>15 then raise exception 'Invalid attachments'; end if;
 for f in select value from jsonb_array_elements(new.attachments) loop
  if f->>'bucket' is distinct from 'school-competition-files' or coalesce(f->>'path','')='' or length(coalesce(f->>'name',''))>240 or coalesce(f->>'kind','') not in ('photo','pdf') then raise exception 'Invalid file reference'; end if;
  if f->>'kind'='photo' then photos:=photos+1;else pdfs:=pdfs+1;end if;
  if not (tg_op='UPDATE' and coalesce(old.attachments,'[]') @> jsonb_build_array(f)) then
   if split_part(f->>'path','/',1)<>auth.uid()::text or f->>'path' !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|pdf)$' or not exists(select 1 from storage.objects o where o.bucket_id='school-competition-files' and o.name=f->>'path') then raise exception 'File not uploaded or not owned'; end if;
  end if;
 end loop;
 if photos>10 or pdfs>5 then raise exception 'At most 10 images and 5 PDFs'; end if;
 new.updated_at:=now();return new;
end $$;
revoke all on function competition_private.guard_record() from public,anon,authenticated;
create trigger competition_record_guard before insert or update on public.competitions for each row execute function competition_private.guard_record();
-- No grants allow replacing the owner or deleting a whole record.
revoke all on public.competitions from anon;
revoke update,delete,truncate,references,trigger on public.competitions from authenticated;
-- Preserve the two existing operations explicitly after narrowing edit privileges.
grant select,insert on public.competitions to authenticated;
grant update(competition_name,competition_type,department,competition_date,organizer,host,competition_level,stage,grade,supervisor,students,result,award_details,awards_count,notes,status,attachments,details,version) on public.competitions to authenticated;
create policy competition_owner_updates on public.competitions for update to authenticated using(deleted_at is null and (created_by=(select auth.uid()) or documentation_private.can_manage())) with check(deleted_at is null and (created_by=(select auth.uid()) or documentation_private.can_manage()));
-- Existing SELECT leadership scope is kept intact; deleted rows are only visible to report administrators.
create policy competition_active_only on public.competitions as restrictive for select to authenticated using(deleted_at is null or documentation_private.can_manage());
create table competition_private.removed(competition_id bigint primary key references public.competitions(id),removed_at timestamptz not null default now(),removed_by uuid not null);
alter table competition_private.removed enable row level security;revoke all on competition_private.removed from public,anon,authenticated;
create or replace function competition_private.delete_record(record_id bigint) returns void language plpgsql security definer set search_path='' as $$
begin
 if not documentation_private.can_manage() then raise exception 'Only report administrators can delete'; end if;
 -- Preserve the original row and all evidence, including the previous version.
 insert into competition_private.revisions(competition_id,changed_by,previous) select id,auth.uid(),to_jsonb(c) from public.competitions c where id=record_id and deleted_at is null;
 -- A separate reversible marker preserves every original field and file.
 insert into competition_private.removed(competition_id,removed_by) values(record_id,auth.uid()) on conflict do nothing;
end $$;
create function competition_private.is_removed(record_id bigint) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from competition_private.removed where competition_id=record_id)$$;
revoke all on function competition_private.is_removed(bigint) from public,anon;grant execute on function competition_private.is_removed(bigint) to authenticated;
create policy competition_not_removed on public.competitions as restrictive for select to authenticated using(not competition_private.is_removed(id));
create policy competition_not_removed_update on public.competitions as restrictive for update to authenticated using(not competition_private.is_removed(id)) with check(not competition_private.is_removed(id));
revoke all on function competition_private.delete_record(bigint) from public,anon;grant execute on function competition_private.delete_record(bigint) to authenticated;
create function public.delete_competition(record_id bigint) returns void language sql security invoker set search_path='' as $$select competition_private.delete_record(record_id)$$;
revoke all on function public.delete_competition(bigint) from public,anon;grant execute on function public.delete_competition(bigint) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('school-competition-files','school-competition-files',false,8388608,array['image/jpeg','application/pdf']) on conflict(id) do nothing;
create policy competition_evidence_upload on storage.objects for insert to authenticated with check(bucket_id='school-competition-files' and split_part(name,'/',1)=(select auth.uid())::text and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|pdf)$' and exists(select 1 from public.profiles where id=(select auth.uid())) and ((name like '%.jpg' and (metadata->>'mimetype')='image/jpeg' and (metadata->>'size')::bigint<=3145728) or (name like '%.pdf' and (metadata->>'mimetype')='application/pdf' and (metadata->>'size')::bigint<=8388608)));
create policy competition_evidence_read on storage.objects for select to authenticated using(bucket_id='school-competition-files' and exists(select 1 from public.competitions c where c.attachments @> jsonb_build_array(jsonb_build_object('bucket','school-competition-files','path',name))));
