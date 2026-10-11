-- Pending school-owner approval. Additive migration; no existing records/accounts modified.
-- Names, account bindings and department grants are a separate PRIVATE import.
begin;
create schema if not exists observation_private;
revoke all on schema observation_private from public, anon;
grant usage on schema observation_private to authenticated;
create table public.observation_teachers (
 id uuid primary key default gen_random_uuid(), user_id uuid unique references auth.users(id),
 full_name text not null check (length(full_name) between 3 and 180),
 department text not null, subject text not null default '',
 position text not null default 'teacher' check(position in ('teacher','first_teacher','coordinator')),
 academic_year text not null check(academic_year ~ '^[0-9]{4}-[0-9]{4}$' and split_part(academic_year,'-',2)::integer=split_part(academic_year,'-',1)::integer+1),
 active boolean not null default true, created_at timestamptz not null default now()
);
create index observation_teachers_department_year on public.observation_teachers(department,academic_year);
create table public.observation_access (
 user_id uuid not null references auth.users(id), department text not null,
 domain_ids smallint[] not null default '{}', can_edit boolean not null default false,
 primary key(user_id,department), check(domain_ids <@ array[1,2,3,4,5]::smallint[])
);
create table public.classroom_visits (
 id uuid primary key default gen_random_uuid(), teacher_id uuid not null references public.observation_teachers(id),
 observer_id uuid not null references auth.users(id), observer_name text not null, observer_role text not null, visit_date date not null,
 academic_year text not null check(academic_year ~ '^[0-9]{4}-[0-9]{4}$' and split_part(academic_year,'-',2)::integer=split_part(academic_year,'-',1)::integer+1), semester smallint not null check(semester in (1,2)),
 visit_type text not null check(visit_type in ('زيارة صفية','زيارة متابعة','زيارة تبادلية')),
 lesson_title text not null check(length(lesson_title) between 1 and 300), subject text not null default '',
 class_section text not null default '', lesson_period text not null default '',
 student_count integer check(student_count between 0 and 1000), absent_count integer check(absent_count between 0 and 1000),
 time_start time, time_end time, visit_number integer check(visit_number>0),
 status text not null default 'draft' check(status in ('draft','final')),
 client_request_id uuid, unique(observer_id,client_request_id),
 version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(absent_count<=student_count), check(time_end>time_start)
);
create index classroom_visits_teacher_date on public.classroom_visits(teacher_id,visit_date,id);
create index classroom_visits_period on public.classroom_visits(academic_year,semester,visit_date);
create table public.classroom_visit_ratings (
 visit_id uuid not null references public.classroom_visits(id), criterion_id smallint not null check(criterion_id between 1 and 18),
 level smallint check(level between 1 and 4), primary key(visit_id,criterion_id)
);
create table public.classroom_visit_details (
 visit_id uuid primary key references public.classroom_visits(id), final_judgment smallint check(final_judgment between 1 and 4),
 judgment_basis text not null default '' check(length(judgment_basis)<=4000),
 skills smallint[] not null default '{}', skills_assessed boolean not null default false,
 student_work smallint[] not null default '{}', work_assessed boolean not null default false,
 sample_count integer check(sample_count between 0 and 100),
 successes text not null default '' check(length(successes)<=12000), development text not null default '' check(length(development)<=12000),
 support smallint[] not null default '{}', support_notes text not null default '' check(length(support_notes)<=12000),
 check(skills <@ array[1,2,3,4,5,6,7,8]::smallint[]), check(student_work <@ array[1,2,3,4,5]::smallint[]), check(support <@ array[1,2,3,4,5,6]::smallint[])
);
create table public.classroom_reports (
 id uuid primary key default gen_random_uuid(), creator_id uuid not null references auth.users(id),
 creator_name text not null, issued_at timestamptz not null default now(), analysis_type text not null,
 filters jsonb not null, comparison_filters jsonb, snapshot jsonb not null, comparison_snapshot jsonb,
 teacher_ids uuid[] not null, criterion_ids smallint[] not null, includes_details boolean not null,
 supervisor_name text not null default ''
);
create index classroom_reports_creator_date on public.classroom_reports(creator_id,issued_at);
-- Protected lookups are private, use current server-owned profiles/grants, never user_metadata.
create function observation_private.domain_for(c integer) returns integer language sql immutable set search_path='' as $$
 select case when c between 1 and 2 then 1 when c between 3 and 7 then 2 when c between 8 and 12 then 3 when c between 13 and 14 then 4 when c between 15 and 18 then 5 end
$$;
create function observation_private.teacher_access(t uuid, writing boolean default false, domain_id integer default null)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists (
  select 1 from public.observation_teachers teacher join public.profiles p on p.id=auth.uid()
  where teacher.id=t and (
   (p.school_access='all' and p.role in ('principal','assistant_principal'))
   or (not writing and teacher.user_id=auth.uid())
   or (p.role in ('assistant_principal','first_teacher','coordinator') and exists (
    select 1 from public.observation_access a where a.user_id=auth.uid() and a.department=teacher.department
    and (not writing or a.can_edit)
    and (domain_id is null or cardinality(a.domain_ids)=0 or (domain_id=0 and a.domain_ids @> array[1,2,3,4,5]::smallint[]) or domain_id=any(a.domain_ids))
   ))
  )
 )
$$;
create function observation_private.visit_access(v uuid, domain_id integer default null) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.classroom_visits x where x.id=v
 and observation_private.teacher_access(x.teacher_id,false,domain_id)
 and (x.status='final' or x.observer_id=auth.uid() and observation_private.teacher_access(x.teacher_id,true,0)))
$$;
create function observation_private.report_access(tids uuid[], cids smallint[], detail boolean) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from unnest(tids) t where not observation_private.teacher_access(t,false,null)
 or (detail and not observation_private.teacher_access(t,false,0))
 or exists(select 1 from unnest(cids) c where not observation_private.teacher_access(t,false,observation_private.domain_for(c))))
 and (cardinality(tids)>0 or exists(select 1 from public.profiles p where p.id=auth.uid() and p.school_access='all' and p.role in ('principal','assistant_principal')))
$$;
alter table public.observation_teachers enable row level security;
alter table public.observation_access enable row level security;
alter table public.classroom_visits enable row level security;
alter table public.classroom_visit_ratings enable row level security;
alter table public.classroom_visit_details enable row level security;
alter table public.classroom_reports enable row level security;
revoke all on public.observation_teachers,public.observation_access,public.classroom_visits,public.classroom_visit_ratings,public.classroom_visit_details,public.classroom_reports from public,anon,authenticated;
grant select on public.observation_teachers,public.observation_access,public.classroom_visits,public.classroom_visit_ratings,public.classroom_visit_details,public.classroom_reports to authenticated;
create policy observation_teachers_read on public.observation_teachers for select to authenticated using(observation_private.teacher_access(id));
create policy observation_access_own on public.observation_access for select to authenticated using(user_id=(select auth.uid()));
create policy classroom_visits_read on public.classroom_visits for select to authenticated using(observation_private.visit_access(id));
create policy classroom_ratings_read on public.classroom_visit_ratings for select to authenticated using(observation_private.visit_access(visit_id,observation_private.domain_for(criterion_id)));
create policy classroom_details_read on public.classroom_visit_details for select to authenticated using(observation_private.visit_access(visit_id,0));
create policy classroom_reports_read on public.classroom_reports for select to authenticated using(observation_private.report_access(teacher_ids,criterion_ids,includes_details));
-- All writes are atomic, explicitly authorized private routines. No direct API table writes.
create function observation_private.save_visit(payload jsonb, ratings jsonb, details jsonb, expected_version integer default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); tid uuid; vid uuid; old public.classroom_visits; desired text; r record; count_valid integer; rev integer; request uuid:=nullif(payload->>'request_id','')::uuid; previous public.classroom_visits;
begin
 if uid is null then raise exception 'يلزم تسجيل الدخول' using errcode='42501'; end if;
 tid:=(payload->>'teacher_id')::uuid; vid:=nullif(payload->>'id','')::uuid; desired:=payload->>'status';
 if not observation_private.teacher_access(tid,true,0) then raise exception 'لا توجد صلاحية لإنشاء أو تعديل زيارة لهذا القسم' using errcode='42501'; end if;
 if (details->>'skills_assessed')::boolean is distinct from true and jsonb_array_length(coalesce(details->'skills','[]'))>0 or (details->>'work_assessed')::boolean is distinct from true and jsonb_array_length(coalesce(details->'student_work','[]'))>0 then raise exception 'يجب تأكيد رصد المحور قبل تسجيل مؤشراته'; end if;
 if desired not in ('draft','final') or desired is null then raise exception 'حالة الزيارة غير صالحة'; end if;
 if not exists(select 1 from public.observation_teachers where id=tid and active and academic_year=payload->>'academic_year') then raise exception 'المعلمة غير مسجلة في العام المختار'; end if;
 if jsonb_typeof(ratings)<>'array' or jsonb_array_length(ratings)<>18 then raise exception 'يجب إرسال المعايير الثمانية عشر'; end if;
 select count(distinct (x->>'criterion_id')::integer) into count_valid from jsonb_array_elements(ratings) x where (x->>'criterion_id')::integer between 1 and 18;
 if count_valid<>18 then raise exception 'معايير مكررة أو غير صالحة'; end if;
 if vid is null and request is not null then
  perform pg_advisory_xact_lock(hashtextextended(uid::text||request::text,0));
  select * into previous from public.classroom_visits where observer_id=uid and client_request_id=request;
  if previous.id is not null then
   if previous.teacher_id<>tid then raise exception 'طلب الحفظ مرتبط بمعلمة أخرى'; end if;
   return jsonb_build_object('id',previous.id,'version',previous.version,'recovered',true);
  end if;
 end if;
 if vid is not null then
  select * into old from public.classroom_visits where id=vid for update;
  if old.id is null or not observation_private.teacher_access(old.teacher_id,true,0) then raise exception 'الزيارة غير متاحة' using errcode='42501'; end if;
  if old.teacher_id<>tid then raise exception 'لا يمكن نقل الزيارة إلى معلمة أخرى'; end if;
  if expected_version is null or old.version<>expected_version then raise exception 'عدلت الزيارة من جلسة أخرى. أعيدي تحميلها قبل الحفظ.' using errcode='40001'; end if;
 else vid:=gen_random_uuid(); end if;
 if desired='final' then
  if (details->>'final_judgment') is null or (details->>'final_judgment')::integer not between 1 and 4 or nullif(btrim(details->>'judgment_basis'),'') is null then raise exception 'اختاري الحكم النهائي وسجلي مبرره وفق الاستمارة'; end if;
  if not exists(select 1 from jsonb_array_elements(ratings) x where (x->>'criterion_id')::integer=1 and (x->>'level')::integer between 1 and 4)
  or not exists(select 1 from jsonb_array_elements(ratings) x where (x->>'criterion_id')::integer=2 and (x->>'level')::integer between 1 and 4) then raise exception 'يلزم تقييم معياري الإنجاز الأكاديمي لاعتماد الحكم'; end if;
 end if;
 rev:=coalesce(old.version,0)+1;
 insert into public.classroom_visits(id,teacher_id,observer_id,observer_name,observer_role,visit_date,academic_year,semester,visit_type,lesson_title,subject,class_section,lesson_period,student_count,absent_count,time_start,time_end,visit_number,status,version,client_request_id)
 values(vid,tid,coalesce(old.observer_id,uid),coalesce(old.observer_name,(select full_name from public.profiles where id=uid)),coalesce(old.observer_role,(select role from public.profiles where id=uid)),(payload->>'visit_date')::date,payload->>'academic_year',(payload->>'semester')::smallint,payload->>'visit_type',payload->>'lesson_title',coalesce(payload->>'subject',''),coalesce(payload->>'class_section',''),coalesce(payload->>'lesson_period',''),nullif(payload->>'student_count','')::integer,nullif(payload->>'absent_count','')::integer,nullif(payload->>'time_start','')::time,nullif(payload->>'time_end','')::time,nullif(payload->>'visit_number','')::integer,desired,rev,request)
 on conflict(id) do update set visit_date=excluded.visit_date,academic_year=excluded.academic_year,semester=excluded.semester,visit_type=excluded.visit_type,lesson_title=excluded.lesson_title,subject=excluded.subject,class_section=excluded.class_section,lesson_period=excluded.lesson_period,student_count=excluded.student_count,absent_count=excluded.absent_count,time_start=excluded.time_start,time_end=excluded.time_end,visit_number=excluded.visit_number,status=excluded.status,version=excluded.version,updated_at=now();
 for r in select * from jsonb_to_recordset(ratings) as x(criterion_id smallint,level smallint) loop
  insert into public.classroom_visit_ratings values(vid,r.criterion_id,r.level) on conflict(visit_id,criterion_id) do update set level=excluded.level;
 end loop;
 insert into public.classroom_visit_details(visit_id,final_judgment,judgment_basis,skills,skills_assessed,student_work,work_assessed,sample_count,successes,development,support,support_notes)
 values(vid,(details->>'final_judgment')::smallint,coalesce(details->>'judgment_basis',''),array(select x::smallint from jsonb_array_elements_text(coalesce(details->'skills','[]')) x),coalesce((details->>'skills_assessed')::boolean,false),array(select x::smallint from jsonb_array_elements_text(coalesce(details->'student_work','[]')) x),coalesce((details->>'work_assessed')::boolean,false),nullif(details->>'sample_count','')::integer,coalesce(details->>'successes',''),coalesce(details->>'development',''),array(select x::smallint from jsonb_array_elements_text(coalesce(details->'support','[]')) x),coalesce(details->>'support_notes',''))
 on conflict(visit_id) do update set final_judgment=excluded.final_judgment,judgment_basis=excluded.judgment_basis,skills=excluded.skills,skills_assessed=excluded.skills_assessed,student_work=excluded.student_work,work_assessed=excluded.work_assessed,sample_count=excluded.sample_count,successes=excluded.successes,development=excluded.development,support=excluded.support,support_notes=excluded.support_notes;
 return jsonb_build_object('id',vid,'version',rev);
end $$;
create function public.save_classroom_visit(payload jsonb,ratings jsonb,details jsonb,expected_version integer default null) returns jsonb language sql security invoker set search_path='' as $$select observation_private.save_visit(payload,ratings,details,expected_version)$$;
-- Authoritative capture: filters are checked and rows are selected on the server, never supplied totals.
create function observation_private.capture(filters jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid(); sc text:=filters->>'scope'; tid uuid:=nullif(filters->>'teacher_id','')::uuid; dep text:=filters->>'department'; yr text:=filters->>'academic_year'; vids uuid[]; out_teachers jsonb; vs jsonb; rs jsonb; ds jsonb; start_date date:=nullif(filters->>'from','')::date; end_date date:=nullif(filters->>'to','')::date; known boolean;
begin
 if uid is null then raise exception 'يلزم تسجيل الدخول' using errcode='42501'; end if;
 if sc not in ('teacher','department','school') or sc is null then raise exception 'نطاق غير صالح'; end if;
 if start_date>end_date then raise exception 'تاريخ البداية بعد النهاية'; end if;
 if sc='school' and not exists(select 1 from public.profiles p where p.id=uid and p.school_access='all' and p.role in ('principal','assistant_principal')) then raise exception 'تحليل المدرسة يتطلب صلاحية جميع الأقسام' using errcode='42501'; end if;
 if sc='teacher' and (tid is null or not observation_private.teacher_access(tid)) then raise exception 'المعلمة غير متاحة' using errcode='42501'; end if;
 if sc='department' and (nullif(dep,'') is null or not exists(select 1 from public.profiles p where p.id=uid and p.school_access='all' and p.role in ('principal','assistant_principal')) and not exists(select 1 from public.observation_access a join public.profiles p on p.id=a.user_id where a.user_id=uid and a.department=dep and p.role in ('assistant_principal','first_teacher','coordinator'))) then raise exception 'القسم غير متاح' using errcode='42501'; end if;
 select coalesce(array_agg(v.id),'{}'),coalesce(jsonb_agg(to_jsonb(v) order by v.visit_date,v.id),'[]') into vids,vs from public.classroom_visits v join public.observation_teachers t on t.id=v.teacher_id
 where v.status='final' and observation_private.teacher_access(t.id) and (sc<>'teacher' or t.id=tid) and (sc<>'department' or t.department=dep)
 and (start_date is null or v.visit_date>=start_date) and (end_date is null or v.visit_date<=end_date)
 and (nullif(yr,'') is null or v.academic_year=yr) and (nullif(filters->>'semester','') is null or v.semester=(filters->>'semester')::smallint)
 and (nullif(filters->>'visit_type','') is null or v.visit_type=filters->>'visit_type')
 and (nullif(filters->>'visit_id','') is null or v.id=(filters->>'visit_id')::uuid);
 select coalesce(jsonb_agg(to_jsonb(r) order by r.visit_id,r.criterion_id),'[]') into rs from public.classroom_visit_ratings r join public.classroom_visits v on v.id=r.visit_id where r.visit_id=any(vids) and observation_private.teacher_access(v.teacher_id,false,observation_private.domain_for(r.criterion_id));
 select coalesce(jsonb_agg(to_jsonb(d)),'[]') into ds from public.classroom_visit_details d join public.classroom_visits v on v.id=d.visit_id where d.visit_id=any(vids) and observation_private.teacher_access(v.teacher_id,false,0);
 select coalesce(jsonb_agg(to_jsonb(t) - 'user_id' order by t.full_name),'[]') into out_teachers from public.observation_teachers t where observation_private.teacher_access(t.id) and (sc<>'teacher' or t.id=tid) and (sc<>'department' or t.department=dep) and (t.id in (select teacher_id from public.classroom_visits where id=any(vids)) or t.active and t.academic_year=yr);
 known:=nullif(yr,'') is not null and exists(select 1 from public.observation_teachers t where t.active and t.academic_year=yr and observation_private.teacher_access(t.id) and (sc<>'teacher' or t.id=tid) and (sc<>'department' or t.department=dep));
 return jsonb_build_object('visits',vs,'ratings',rs,'details',ds,'teachers',out_teachers,'coverage_known',known,'coverage_teacher_ids',(select coalesce(jsonb_agg(t.id),'[]') from public.observation_teachers t where t.active and t.academic_year=yr and observation_private.teacher_access(t.id) and (sc<>'teacher' or t.id=tid) and (sc<>'department' or t.department=dep)));
end $$;
create function public.analyze_classroom_visits(filters jsonb) returns jsonb language sql security invoker set search_path='' as $$select observation_private.capture(filters)$$;
create function observation_private.save_report(filters jsonb,comparison_filters jsonb,analysis_type text,supervisor_name text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare s jsonb; b jsonb; rid uuid; name text; tids uuid[]; cids smallint[]; details_present boolean;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول' using errcode='42501'; end if;
 if analysis_type not in ('domains-chart','domains-description','domains-brief','all-criteria','judgment-chart','judgment-description','judgment-brief','skills','work','feedback','unified-count','unified-percent','visit-form') then raise exception 'نوع التحليل غير صالح'; end if;
 if length(supervisor_name)>180 then raise exception 'اسم المشرفة طويل'; end if;
 s:=observation_private.capture(filters); if comparison_filters is not null then b:=observation_private.capture(comparison_filters); end if;
 select p.full_name into name from public.profiles p where p.id=auth.uid();
 select coalesce(array_agg(distinct (x->>'id')::uuid),'{}') into tids from (select value x from jsonb_array_elements(s->'teachers') union all select value from jsonb_array_elements(coalesce(b->'teachers','[]'))) q;
 select coalesce(array_agg(distinct (x->>'criterion_id')::smallint),'{}') into cids from (select value x from jsonb_array_elements(s->'ratings') union all select value from jsonb_array_elements(coalesce(b->'ratings','[]'))) q;
 details_present:=jsonb_array_length(s->'details')>0 or jsonb_array_length(coalesce(b->'details','[]'))>0;
 insert into public.classroom_reports(creator_id,creator_name,analysis_type,filters,comparison_filters,snapshot,comparison_snapshot,teacher_ids,criterion_ids,includes_details,supervisor_name)
 values(auth.uid(),coalesce(name,'مستخدمة البوابة'),analysis_type,filters,comparison_filters,s,b,tids,cids,details_present,supervisor_name) returning id into rid;
 return rid;
end $$;
create function public.save_classroom_report(filters jsonb,comparison_filters jsonb,analysis_type text,supervisor_name text default '') returns uuid language sql security invoker set search_path='' as $$select observation_private.save_report(filters,comparison_filters,analysis_type,supervisor_name)$$;
-- Deny the default PUBLIC execution permission on every new function.
revoke execute on all functions in schema observation_private from public,anon;
grant execute on all functions in schema observation_private to authenticated;
revoke all on function public.save_classroom_visit(jsonb,jsonb,jsonb,integer),public.analyze_classroom_visits(jsonb),public.save_classroom_report(jsonb,jsonb,text,text) from public,anon;
grant execute on function public.save_classroom_visit(jsonb,jsonb,jsonb,integer),public.analyze_classroom_visits(jsonb),public.save_classroom_report(jsonb,jsonb,text,text) to authenticated;
commit;
