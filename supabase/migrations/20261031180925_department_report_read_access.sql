-- Read-only report scopes are deliberately separate from report_scope_delegates (which permits editing).
create table documentation_private.report_read_scopes(
 user_id uuid not null references public.profiles(id),
 scope_kind text not null check(scope_kind in ('department','committee')),
 scope_value text not null,
 tag_id bigint references public.school_tags(id),
 granted_by uuid references public.profiles(id),
 granted_at timestamptz not null default now(),
 primary key(user_id,scope_kind,scope_value),
 check((scope_kind='department' and tag_id is null and btrim(scope_value)<>'') or (scope_kind='committee' and tag_id is not null and scope_value=tag_id::text))
);
alter table documentation_private.report_read_scopes enable row level security;
revoke all on documentation_private.report_read_scopes from public,anon,authenticated;
create table documentation_private.report_read_scope_history(id bigint generated always as identity primary key,actor uuid,changed_at timestamptz not null default now(),subject uuid,department text,enabled boolean);
alter table documentation_private.report_read_scope_history enable row level security;
revoke all on documentation_private.report_read_scope_history from public,anon,authenticated;

-- These are existing, explicit department assignments, not grants inferred from job titles alone.
insert into documentation_private.report_read_scopes(user_id,scope_kind,scope_value)
 select a.user_id,'department',a.department from public.observation_access a join public.profiles p on p.id=a.user_id
 where a.can_edit and p.role in('first_teacher','coordinator');
-- The council is an existing catalogue record; the exact verified account is bound by UUID.
insert into documentation_private.report_read_scopes(user_id,scope_kind,scope_value,tag_id)
 select p.id,'committee',t.id::text,t.id from public.profiles p cross join public.school_tags t
 where p.id='49a1b172-33cb-40f8-bd77-20fbcbbb712d' and p.full_name='احلام محمد ناجي الصغيري'
 and t.kind='committee' and t.name='المجلس الطلابي';

do $$begin
 if not exists(select 1 from documentation_private.report_read_scopes where user_id='49a1b172-33cb-40f8-bd77-20fbcbbb712d' and scope_kind='committee') then raise exception 'لم تتأكد مطابقة حساب أحلام وتصنيف المجلس الطلابي.';end if;
end$$;

create function documentation_private.legacy_tag_names(value text) returns text[] language plpgsql immutable set search_path='' as $$
declare j jsonb;begin
 begin j:=value::jsonb;exception when others then j:=null;end;
 if jsonb_typeof(j)='array' then return array(select jsonb_array_elements_text(j));end if;
 return array(select btrim(v) from unnest(regexp_split_to_array(coalesce(value,''),'[•،,\n]')) v);
end$$;
revoke all on function documentation_private.legacy_tag_names(text) from public,anon,authenticated;

create function documentation_private.has_report_department(dept text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from documentation_private.report_read_scopes s where s.user_id=auth.uid() and s.scope_kind='department' and s.scope_value=dept)
$$;
revoke all on function documentation_private.has_report_department(text) from public,anon;
grant execute on function documentation_private.has_report_department(text) to authenticated;

create function documentation_private.delegated_report_read(doc bigint) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid()) and exists(
 select 1 from public.documentations d where d.id=doc and d.deleted_at is null and d.status='published'
 and coalesce(d.details->>'confidential','false') not in('true','1')
 and coalesce(d.details->>'isConfidential','false') not in('true','1')
 and coalesce(d.details->>'sensitive','false') not in('true','1')
 and coalesce(d.details->>'isSensitive','false') not in('true','1')
 and coalesce(d.details->>'visibility','') not in('private','confidential','restricted','secret')
 and coalesce(d.activity_type,'') <> 'مقابلة وحوار خاص'
 and not coalesce(documentation_private.is_recognition(d.details,d.projects),false)
 and nullif(btrim(coalesce(d.competition_students,'')),'') is null
 and nullif(btrim(coalesce(d.details->>'docCompetitionStudents','')),'') is null
 and coalesce(d.details->'students','[]'::jsonb) in ('[]'::jsonb,'null'::jsonb)
 and not exists(select 1 from public.competitions c where c.legacy_documentation_id=d.id and coalesce(c.students,'[]'::jsonb)<>'[]'::jsonb)
 and not exists(select 1 from public.meeting_minutes m where m.documentation_id=d.id and m.kind='students')
 and exists(select 1 from documentation_private.report_read_scopes s where s.user_id=auth.uid() and (
  (s.scope_kind='department' and (s.scope_value=d.department or d.activity_type='اجتماع' and exists(select 1 from public.meeting_minutes m where m.documentation_id=d.id and s.scope_value=any(m.departments))))
  or (s.scope_kind='committee' and exists(select 1 from public.school_tags t where t.id=s.tag_id and t.kind='committee' and (
    exists(select 1 from public.documentation_tags l where l.documentation_id=d.id and l.tag_id=t.id)
    or (case when jsonb_typeof(d.details->'committees')='array' then d.details->'committees' else '[]'::jsonb end) ? t.name
    or t.name=any(documentation_private.legacy_tag_names(d.committees))
  )))
 ))
 )
$$;
revoke all on function documentation_private.delegated_report_read(bigint) from public,anon;
grant execute on function documentation_private.delegated_report_read(bigint) to authenticated;
create policy department_and_council_reports_read on public.documentations for select to authenticated using(documentation_private.delegated_report_read(id));

create table documentation_private.report_read_deployment_backup as select now() backed_up_at,pg_get_functiondef('meeting_private.read(bigint)'::regprocedure) meeting_read_definition;
alter table documentation_private.report_read_deployment_backup enable row level security;
revoke all on documentation_private.report_read_deployment_backup from public,anon,authenticated;

-- Preserve all original meeting permissions; extend only published, non-student, non-confidential meetings.
create or replace function meeting_private.read(doc bigint) returns boolean language sql stable security definer set search_path='' as $$
 select meeting_private.member() and exists(select 1 from public.documentations d join public.meeting_minutes m on m.documentation_id=d.id where d.id=doc and d.deleted_at is null and (
 d.created_by=auth.uid() or documentation_private.can_manage()
 or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('principal','assistant_principal') and (p.school_access='all' or exists(select 1 from public.observation_access a where a.user_id=p.id and a.department=any(m.departments) and a.can_edit)))
 or d.status='published' and exists(select 1 from public.meeting_participants p where p.documentation_id=d.id and p.user_id=auth.uid() and (p.attendance='present' or p.attendance='absent' and p.share_absent))
 or documentation_private.delegated_report_read(d.id)
 ))
$$;

create function documentation_private.department_report_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare deps text[];begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 if documentation_private.can_manage() then
  select array_agg(distinct dep order by dep) into deps from (select unnest(case when cardinality(p.departments)>0 then p.departments else array[p.department] end) dep from public.profiles p union select department from public.observation_access) t where nullif(btrim(dep),'') is not null;
 else select array_agg(scope_value order by scope_value) into deps from documentation_private.report_read_scopes where user_id=auth.uid() and scope_kind='department';end if;
 deps:=coalesce(deps,'{}');
 return jsonb_build_object('departments',deps,'can_manage',documentation_private.can_manage(),'staff',coalesce((
 select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'job_title',p.job_title,'departments',case when cardinality(p.departments)>0 then p.departments else array[p.department] end) order by p.full_name)
 from public.profiles p where (case when cardinality(p.departments)>0 then p.departments else array[p.department] end)&&deps
 or exists(select 1 from public.documentations d where d.created_by=p.id and d.department=any(deps) and documentation_private.delegated_report_read(d.id))
 ),'[]'::jsonb));
end$$;
revoke all on function documentation_private.department_report_context() from public,anon;
grant execute on function documentation_private.department_report_context() to authenticated;
create function public.department_report_context() returns jsonb language sql stable security invoker set search_path='' as $$select documentation_private.department_report_context()$$;
revoke all on function public.department_report_context() from public,anon;
grant execute on function public.department_report_context() to authenticated;

create function documentation_private.set_department_report_reader(subject_id uuid,dept text,enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not documentation_private.can_manage() then raise exception 'صلاحية الإدارة مطلوبة.' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=subject_id) or not exists(select 1 from public.profiles p where dept=p.department or dept=any(p.departments) union all select 1 from public.observation_access where department=dept) then raise exception 'الحساب أو القسم غير مسجل.';end if;
 if enabled then insert into documentation_private.report_read_scopes(user_id,scope_kind,scope_value,granted_by) values(subject_id,'department',dept,auth.uid()) on conflict(user_id,scope_kind,scope_value) do nothing;
 else delete from documentation_private.report_read_scopes where user_id=subject_id and scope_kind='department' and scope_value=dept;end if;
 insert into documentation_private.report_read_scope_history(actor,subject,department,enabled) values(auth.uid(),subject_id,dept,enabled);
end$$;
revoke all on function documentation_private.set_department_report_reader(uuid,text,boolean) from public,anon;
grant execute on function documentation_private.set_department_report_reader(uuid,text,boolean) to authenticated;
create function public.set_department_report_reader(subject_id uuid,dept text,enabled boolean) returns void language sql security invoker set search_path='' as $$select documentation_private.set_department_report_reader(subject_id,dept,enabled)$$;
revoke all on function public.set_department_report_reader(uuid,text,boolean) from public,anon;
grant execute on function public.set_department_report_reader(uuid,text,boolean) to authenticated;
