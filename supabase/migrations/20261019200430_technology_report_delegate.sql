-- Scope-specific delegation: existing administration/deletion and staff roles stay unchanged.
create table documentation_private.report_scope_delegates(
 user_id uuid not null references public.profiles(id),scope_kind text not null check(scope_kind in('department','project')),scope_value text not null,
 primary key(user_id,scope_kind,scope_value)
);
alter table documentation_private.report_scope_delegates enable row level security;
revoke all on documentation_private.report_scope_delegates from public,anon,authenticated;
do $$declare uid uuid;begin
 if (select count(*) from public.profiles where full_name='Eman Jameel Hussain Alqassab')<>1 then raise exception 'Verify Eman Alqassab account identity';end if;
 select id into uid from public.profiles where full_name='Eman Jameel Hussain Alqassab';
 insert into documentation_private.report_scope_delegates values(uid,'department','تكنولوجيا التعليم'),(uid,'project','بصمات رقمية');
end$$;
create function documentation_private.scoped_report_access(dept text,project_text text,detail jsonb,removed timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and removed is null and exists(select 1 from documentation_private.report_scope_delegates s where s.user_id=auth.uid() and
 (s.scope_kind='department' and s.scope_value=dept or s.scope_kind='project' and
 (case when jsonb_typeof(detail->'projects')='array' then detail->'projects' else to_jsonb(string_to_array(coalesce(project_text,''),' • ')) end)?s.scope_value))
$$;
revoke all on function documentation_private.scoped_report_access(text,text,jsonb,timestamptz) from public,anon;
grant execute on function documentation_private.scoped_report_access(text,text,jsonb,timestamptz) to authenticated;
create policy scoped_report_read on public.documentations for select to authenticated using(documentation_private.scoped_report_access(department,projects,details,deleted_at));
create policy scoped_report_edit on public.documentations for update to authenticated
using(documentation_private.scoped_report_access(department,projects,details,deleted_at))
with check(documentation_private.scoped_report_access(department,projects,details,deleted_at));
create or replace function documentation_private.guard_report_edit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not (documentation_private.can_edit_report(old.created_by,old.activity_type,old.department,old.deleted_at) or documentation_private.scoped_report_access(old.department,old.projects,old.details,old.deleted_at)) then raise exception 'ليست لديكِ صلاحية تعديل هذا التقرير.' using errcode='42501';end if;
 if new.last_edit_request is null or new.last_edit_request is not distinct from old.last_edit_request then raise exception 'معرّف محاولة التعديل غير صالح. أعيدي فتح التقرير.';end if;
 if new.created_by is distinct from old.created_by or new.request_id is distinct from old.request_id or new.id<>old.id or new.deleted_at is distinct from old.deleted_at then raise exception 'لا يجوز تغيير هوية التقرير أو حالة الحذف.' using errcode='42501';end if;
 if nullif(btrim(new.activity),'') is null then raise exception 'اسم الفعالية مطلوب.';end if;
 new.edit_version:=old.edit_version+1;new.edited_by:=auth.uid();new.updated_at:=clock_timestamp();
 new.academic_year:=coalesce(nullif(new.details->>'academicYear',''),old.academic_year);
 insert into documentation_private.report_edit_history(documentation_id,actor_id,previous_record) values(old.id,auth.uid(),to_jsonb(old));
 return new;
end $$;
revoke all on function documentation_private.guard_report_edit() from public,anon,authenticated;
create or replace function public.report_edit_context(report_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$
select jsonb_build_object('can_edit',(documentation_private.can_edit_report(d.created_by,d.activity_type,d.department,d.deleted_at) or documentation_private.scoped_report_access(d.department,d.projects,d.details,d.deleted_at)) and (not documentation_private.is_recognition(d.details,d.projects) or documentation_private.recognition_allowed(true)), 'version',d.edit_version) from public.documentations d where d.id=report_id
$$;
insert into public.school_tags(kind,name) values('project','بصمات رقمية') on conflict(kind,name) do nothing;
