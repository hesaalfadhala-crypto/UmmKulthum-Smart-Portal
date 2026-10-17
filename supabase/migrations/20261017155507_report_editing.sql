-- Targeted report editing. No DELETE grant and no changes to existing staff roles.
alter table public.documentations add column if not exists updated_at timestamptz not null default now();
alter table public.documentations add column edit_version integer not null default 0,
 add column last_edit_request uuid, add column edited_by uuid references public.profiles(id);
create table documentation_private.report_editors(user_id uuid primary key references public.profiles(id),manage_center boolean not null default false);
alter table documentation_private.report_editors enable row level security;
revoke all on documentation_private.report_editors from public,anon,authenticated;
-- Delegate binding is applied privately after verifying the exact school account.
create function documentation_private.can_edit_report(owner_id uuid,typ text,dept text,removed timestamptz) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and removed is null and exists(select 1 from documentation_private.report_editors e where e.user_id=auth.uid() and
 (owner_id=auth.uid() or e.manage_center and support_private.manager() and (dept='مركز الدعم والتطوير المهني' or typ='ورشة تدريبية')))
$$;
revoke all on function documentation_private.can_edit_report(uuid,text,text,timestamptz) from public,anon;
grant execute on function documentation_private.can_edit_report(uuid,text,text,timestamptz) to authenticated;
create policy designated_report_editors on public.documentations for update to authenticated
using(documentation_private.can_edit_report(created_by,activity_type,department,deleted_at))
with check(documentation_private.can_edit_report(created_by,activity_type,department,deleted_at));
create policy recognition_update_guard on public.documentations as restrictive for update to authenticated
using(not documentation_private.is_recognition(details,projects) or documentation_private.recognition_allowed(true))
with check(not documentation_private.is_recognition(details,projects) or documentation_private.recognition_allowed(true));
-- Column grants cannot change ownership, creation/request identity, deletion state, or audit attribution.
grant update(activity,activity_type,semester,department,executor,activity_date,location,goal,implementation,results,
 documentation_area,projects,committees,target_categories,competition_type,competition_organizer,competition_host,
 competition_level,competition_students,competition_result,competition_details,workshop_type,executing_agency,
 support_program_id,training_beneficiaries,attachment_files,details,photo_files,execution_scope,organizing_entity,
 hosting_entity,last_edit_request) on public.documentations to authenticated;
create table documentation_private.report_edit_history(id bigint generated always as identity primary key,documentation_id bigint not null references public.documentations(id),actor_id uuid not null,changed_at timestamptz not null default now(),previous_record jsonb not null);
alter table documentation_private.report_edit_history enable row level security;
revoke all on documentation_private.report_edit_history from public,anon,authenticated;
create function documentation_private.guard_report_edit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not documentation_private.can_edit_report(old.created_by,old.activity_type,old.department,old.deleted_at) then raise exception 'ليست لديكِ صلاحية تعديل هذا التقرير.' using errcode='42501';end if;
 if new.last_edit_request is null or new.last_edit_request is not distinct from old.last_edit_request then raise exception 'معرّف محاولة التعديل غير صالح. أعيدي فتح التقرير.';end if;
 if new.created_by is distinct from old.created_by or new.request_id is distinct from old.request_id or new.id<>old.id or new.deleted_at is distinct from old.deleted_at then raise exception 'لا يجوز تغيير هوية التقرير أو حالة الحذف.' using errcode='42501';end if;
 if nullif(btrim(new.activity),'') is null then raise exception 'اسم الفعالية مطلوب.';end if;
 new.edit_version:=old.edit_version+1;new.edited_by:=auth.uid();new.updated_at:=clock_timestamp();
 new.academic_year:=coalesce(nullif(new.details->>'academicYear',''),old.academic_year);
 insert into documentation_private.report_edit_history(documentation_id,actor_id,previous_record) values(old.id,auth.uid(),to_jsonb(old));
 return new;
end $$;
revoke all on function documentation_private.guard_report_edit() from public,anon,authenticated;
create trigger documentation_edit_guard before update of activity,activity_type,semester,department,executor,activity_date,location,goal,implementation,results,documentation_area,projects,committees,target_categories,competition_type,competition_organizer,competition_host,competition_level,competition_students,competition_result,competition_details,workshop_type,executing_agency,support_program_id,training_beneficiaries,attachment_files,details,photo_files,execution_scope,organizing_entity,hosting_entity,last_edit_request on public.documentations for each row execute function documentation_private.guard_report_edit();
-- Retain original validation on inserts. Edits may keep old references or attach files uploaded
-- by the current editor for this exact edit attempt. Removing a reference never deletes a blob.
create function documentation_private.validate_edit_files(refs jsonb,previous_refs jsonb,bucket text,request uuid,maximum integer,extension text,maximum_size bigint) returns void language plpgsql security definer set search_path='' as $$
declare f jsonb;prefix text:=auth.uid()::text||'/'||request::text||'/';
begin
 if auth.uid() is null or request is null or jsonb_typeof(refs) is distinct from 'array' or jsonb_array_length(refs)>maximum then raise exception 'قائمة المرفقات غير صالحة.';end if;
 if (select count(distinct value->>'path') from jsonb_array_elements(refs))<>jsonb_array_length(refs) then raise exception 'لا يجوز تكرار المرفق نفسه.';end if;
 for f in select value from jsonb_array_elements(refs) loop
  if previous_refs @> jsonb_build_array(f) then continue;end if;
  if f->>'bucket' is distinct from bucket or coalesce(f->>'path','') !~ ('^'||prefix||'[a-f0-9-]{36}\.'||extension||'$')
    or not exists(select 1 from storage.objects o where o.bucket_id=bucket and o.name=f->>'path' and coalesce(o.owner_id,o.owner::text)=auth.uid()::text and coalesce((o.metadata->>'size')::bigint,0) between 1 and maximum_size)
  then raise exception 'المرفق الجديد غير محفوظ أو لا يخص محاولة التعديل الحالية.' using errcode='23514';end if;
 end loop;
end $$;
revoke all on function documentation_private.validate_edit_files(jsonb,jsonb,text,uuid,integer,text,bigint) from public,anon,authenticated;
create or replace function school_documentation_internal.validate_documentation_photos()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare photo jsonb; expected_prefix text;
begin
 if TG_OP='UPDATE' then perform documentation_private.validate_edit_files(new.photo_files,old.photo_files,'school-documentation-images',new.last_edit_request,10,'jpg',3145728);return new;end if;

  if auth.uid() is not null and new.created_by is distinct from auth.uid() then
    raise exception 'Creator does not match the signed-in user' using errcode = '42501';
  end if;
  if auth.uid() is null and current_setting('role', true) in ('anon', 'authenticated') then
    raise exception 'A signed-in creator is required' using errcode = '42501';
  end if;
  if jsonb_typeof(new.photo_files) <> 'array' or jsonb_array_length(new.photo_files) > 10 then
    raise exception 'A documentation must contain at most ten photo references' using errcode = '23514';
  end if;
  if jsonb_array_length(new.photo_files) = 0 then return new; end if;
  if new.request_id is null then
    raise exception 'Photo references require a submission identifier' using errcode = '23514';
  end if;
  expected_prefix := new.created_by::text || '/' || new.request_id::text || '/';
  for photo in select value from jsonb_array_elements(new.photo_files) loop
    if jsonb_typeof(photo) <> 'object'
       or photo->>'bucket' is distinct from 'school-documentation-images'
       or coalesce(photo->>'path', '') !~ ('^' || expected_prefix || '[0-9a-f-]{36}\.jpg$') then
      raise exception 'Invalid documentation photo reference' using errcode = '23514';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'school-documentation-images' and o.name = photo->>'path'
        and coalesce(o.owner_id, o.owner::text) = new.created_by::text
    ) then
      raise exception 'Photo upload is missing or belongs to another user' using errcode = '23514';
    end if;
  end loop;
  return new;
end;
$$;
create or replace function documentation_private.validate_attachments() returns trigger language plpgsql security definer set search_path='' as $$
declare f jsonb;
begin
 if TG_OP='UPDATE' then perform documentation_private.validate_edit_files(new.attachment_files,old.attachment_files,'school-report-files',new.last_edit_request,5,'pdf',8388608);return new;end if;

 if jsonb_array_length(new.attachment_files)>5 then raise exception 'يمكن إرفاق خمسة ملفات PDF كحد أقصى.';end if;
 for f in select * from jsonb_array_elements(new.attachment_files) loop
  if f->>'bucket' is distinct from 'school-report-files' or split_part(f->>'path','/',1) is distinct from new.created_by::text or split_part(f->>'path','/',2) is distinct from new.request_id::text or length(coalesce(f->>'name','')) not between 1 and 250 or not exists(select 1 from storage.objects o where o.bucket_id='school-report-files' and o.name=f->>'path' and coalesce((o.metadata->>'size')::bigint,0) between 1 and 8388608) then raise exception 'مرفق التقرير غير صالح أو لا يخص هذه المحاولة.';end if;
 end loop;return new;
end $$;
drop trigger documentation_attachment_check on public.documentations;
create trigger documentation_attachment_check before insert or update of attachment_files on public.documentations for each row execute function documentation_private.validate_attachments();
-- Content validators run on edits; trash/restore updates do not touch these fields.
create trigger documentation_edit_choices before update of details on public.documentations for each row execute function documentation_private.resolve_other_choices();
create trigger documentation_edit_execution before update of details on public.documentations for each row execute function documentation_private.validate_execution_recognition();
create function public.report_edit_context(report_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$
select jsonb_build_object('can_edit',documentation_private.can_edit_report(d.created_by,d.activity_type,d.department,d.deleted_at) and (not documentation_private.is_recognition(d.details,d.projects) or documentation_private.recognition_allowed(true)), 'version',d.edit_version) from public.documentations d where d.id=report_id
$$;
revoke all on function public.report_edit_context(bigint) from public,anon;
grant execute on function public.report_edit_context(bigint) to authenticated;
