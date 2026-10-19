-- Sanitized aggregate API. Existing documents, ownership, grants and report RLS stay unchanged.
create schema achievement_private;
revoke all on schema achievement_private from public,anon;
grant usage on schema achievement_private to authenticated;
create table achievement_private.reviews(
 report_id bigint primary key references public.documentations(id),
 state text not null check(state in('approved','excluded')),
 report_version integer not null,
 reason text not null default '' check(length(reason)<=500),
 reviewed_by uuid not null references public.profiles(id), reviewed_at timestamptz not null default now()
);
alter table achievement_private.reviews enable row level security;
revoke all on achievement_private.reviews from public,anon,authenticated;
create policy leader_review_read on achievement_private.reviews for select to authenticated using((select documentation_private.can_manage()));
create table achievement_private.review_history(
 id bigint generated always as identity primary key, report_id bigint not null references public.documentations(id),
 state text not null, report_version integer not null, reason text not null,
 reviewed_by uuid not null references public.profiles(id), reviewed_at timestamptz not null default now()
);
alter table achievement_private.review_history enable row level security;
revoke all on achievement_private.review_history from public,anon,authenticated;
-- No raw report content or identifiers leave this view through the statistics endpoint.
create view achievement_private.candidates as
select d.id,d.created_by,d.activity_date,d.edit_version,d.deleted_at,
 coalesce(nullif(btrim(d.activity_type),''),nullif(d.details->>'type',''),'غير محدد') as kind,
 coalesce(nullif(btrim(case when d.department='أخرى' then coalesce(d.details#>>'{otherDetails,department}',d.details->>'departmentOther') else d.department end),''),'غير محدد') as department,
 coalesce(nullif(d.academic_year,''),case when extract(month from d.activity_date)>=9 then extract(year from d.activity_date)::int||'-'||(extract(year from d.activity_date)::int+1) else (extract(year from d.activity_date)::int-1)||'-'||extract(year from d.activity_date)::int end) as academic_year,
 d.semester,
 (nullif(btrim(d.activity),'') is not null and d.activity_date is not null
 and nullif(btrim(d.activity_type),'') is not null and nullif(btrim(d.department),'') is not null
 and nullif(btrim(d.goal),'') is not null and nullif(btrim(d.implementation),'') is not null
 and nullif(btrim(d.results),'') is not null) as complete,
 (d.details ? 'qa_marker' or coalesce(d.details->>'is_test','false')='true' or coalesce(d.details->>'isTest','false')='true'
 or coalesce(d.details->>'is_duplicate','false')='true'
 or coalesce(d.activity,'') ~* '(تجريب|اختبار تقني|اختبار آلي|\mQA\M|\mtest\M|\mdemo\M)') as test_record,
 md5(jsonb_build_array(d.created_by,d.activity_date,lower(regexp_replace(btrim(d.activity),'\s+',' ','g')),d.activity_type,
 regexp_replace(btrim(coalesce(d.goal,'')),'\s+',' ','g'),regexp_replace(btrim(coalesce(d.implementation,'')),'\s+',' ','g'),regexp_replace(btrim(coalesce(d.results,'')),'\s+',' ','g'))::text) as fingerprint,
 r.state as review_state,r.report_version as reviewed_version
from public.documentations d left join achievement_private.reviews r on r.report_id=d.id;
revoke all on achievement_private.candidates from public,anon,authenticated;
create function achievement_private.report_context(report_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r record;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 if not documentation_private.can_manage() then return jsonb_build_object('can_review',false);end if;
 select * into r from achievement_private.candidates c where c.id=report_id;
 if not found then raise exception 'التقرير غير موجود.';end if;
 return jsonb_build_object('can_review',true,'complete',r.complete,'test_record',r.test_record,'deleted',r.deleted_at is not null,
 'version',r.edit_version,'state',case when r.reviewed_version=r.edit_version then coalesce(r.review_state,'pending') else 'pending' end);
end $$;
create function achievement_private.review_report(report_id bigint,decision text,expected_version integer,note text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;
begin
 if auth.uid() is null or not documentation_private.can_manage() then raise exception 'اعتماد الاحتساب متاح للمديرة وحصه فقط.' using errcode='42501';end if;
 if decision not in('approved','excluded') or decision is null or length(coalesce(note,''))>500 then raise exception 'قرار المراجعة غير صالح.';end if;
 perform 1 from public.documentations where id=report_id for update;
 select * into r from achievement_private.candidates c where c.id=report_id;
 if not found or r.deleted_at is not null then raise exception 'التقرير غير متاح للاحتساب.';end if;
 if expected_version is distinct from r.edit_version then raise exception 'تغير التقرير؛ أعيدي فتحه قبل الاعتماد.';end if;
 if decision='approved' and (not r.complete or r.test_record) then raise exception 'لا يمكن احتساب تقرير تجريبي أو غير مكتمل.';end if;
 if decision='excluded' and nullif(btrim(note),'') is null then raise exception 'اكتبي سبب الاستبعاد (تجريبي، مكرر، أو غير ذلك).';end if;
 insert into achievement_private.reviews values(report_id,decision,r.edit_version,coalesce(note,''),auth.uid(),now())
 on conflict on constraint reviews_pkey do update set state=excluded.state,report_version=excluded.report_version,reason=excluded.reason,reviewed_by=excluded.reviewed_by,reviewed_at=excluded.reviewed_at;
 insert into achievement_private.review_history(report_id,state,report_version,reason,reviewed_by) values(report_id,decision,r.edit_version,coalesce(note,''),auth.uid());
 return achievement_private.report_context(report_id);
end $$;
create function achievement_private.dashboard(period text,year_start integer,department_filter text,kind_filter text,project_filter text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone 'Asia/Bahrain')::date; ys date; ye date; start_date date; end_date date; sem text; result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 if period is null or period not in('week','month','semester1','semester2','year') or year_start is null or year_start not between 2000 and 2100
 or length(coalesce(department_filter,''))>300 or length(coalesce(kind_filter,''))>300 or length(coalesce(project_filter,''))>300 then raise exception 'فلاتر الإحصائيات غير صالحة.';end if;
 ys:=make_date(year_start,9,1);ye:=make_date(year_start+1,9,1);
 start_date:=case period when 'week' then today-extract(dow from today)::int when 'month' then date_trunc('month',today)::date else ys end;
 end_date:=case period when 'week' then start_date+7 when 'month' then (start_date+interval '1 month')::date else ye end;
 sem:=case period when 'semester1' then 'الفصل الدراسي الأول' when 'semester2' then 'الفصل الدراسي الثاني' else null end;
 with approved as (
 select c.*,row_number() over(partition by c.fingerprint order by c.id) duplicate_order
 from achievement_private.candidates c join public.profiles p on p.id=c.created_by
 where c.deleted_at is null and c.complete and not c.test_record and c.review_state='approved' and c.reviewed_version=c.edit_version
 and c.activity_date<=today
 ), annual as (
 select a.* from approved a where a.duplicate_order=1 and a.academic_year=year_start||'-'||(year_start+1)
 and a.activity_date>=ys and a.activity_date<ye
 and (coalesce(department_filter,'')='' or a.department=department_filter)
 and (coalesce(kind_filter,'')='' or a.kind=kind_filter)
 and (coalesce(project_filter,'')='' or exists(select 1 from public.documentation_tags dt join public.school_tags st on st.id=dt.tag_id where dt.documentation_id=a.id and st.kind='project' and st.name=project_filter))
 ), selected as (
 select * from annual a where a.activity_date>=start_date and a.activity_date<end_date and (sem is null or a.semester=sem)
 ), known_departments as (select distinct btrim(dept) department from public.profiles p cross join lateral unnest(case when cardinality(p.departments)>0 then p.departments else array[p.department] end) dept where nullif(btrim(dept),'') is not null union select distinct department from approved where duplicate_order=1),
 depts as (select k.department,count(s.id) total from known_departments k left join selected s on s.department=k.department where coalesce(department_filter,'')='' or k.department=department_filter group by k.department),
 people as (select a.created_by,count(*) total from selected a group by a.created_by),
 participants as (select p.full_name,coalesce(p.department,'') department,coalesce(p.job_title,'') job_title,n.total,
 row_number() over(order by n.total desc,p.full_name collate "C",p.id) rank,p.id=auth.uid() is_self from people n join public.profiles p on p.id=n.created_by),
 monthly as (select a.department,to_char(a.activity_date,'YYYY-MM') as month_key,count(*) total from annual a group by a.department,to_char(a.activity_date,'YYYY-MM')),
 monthly_people as (select p.full_name,count(*) total from annual a join public.profiles p on p.id=a.created_by where date_trunc('month',a.activity_date)=date_trunc('month',today) group by p.id,p.full_name),
 monthly_depts as (select a.department,count(*) total from annual a where date_trunc('month',a.activity_date)=date_trunc('month',today) group by a.department)
 select jsonb_build_object(
 'updated_at',now(),'can_review',documentation_private.can_manage(),'period',period,'start_date',greatest(start_date,ys),'end_date',least(end_date,ye)-1,'semester',sem,
 'totals',jsonb_build_object('reports',(select count(*) from selected),'departments',(select count(*) from depts where total>0),'users',(select count(*) from people),
 'week',(select count(*) from annual where activity_date>=today-extract(dow from today)::int and activity_date<today-extract(dow from today)::int+7),
 'month',(select count(*) from annual where date_trunc('month',activity_date)=date_trunc('month',today)),
 'semester',(select count(*) from annual where semester=coalesce(sem,case when extract(month from today)>=9 or extract(month from today)=1 then 'الفصل الدراسي الأول' else 'الفصل الدراسي الثاني' end))),
 'departments',coalesce((select jsonb_agg(jsonb_build_object('name',department,'total',total) order by total desc,department) from depts),'[]'::jsonb),
 'participants',coalesce((select jsonb_agg(to_jsonb(p) order by rank) from participants p),'[]'::jsonb),
 'own_total',(select count(*) from selected where created_by=auth.uid()),
 'own_monthly',coalesce((select jsonb_agg(jsonb_build_object('month',month_key,'total',total) order by month_key) from (select to_char(activity_date,'YYYY-MM') as month_key,count(*) total from annual where created_by=auth.uid() group by to_char(activity_date,'YYYY-MM')) m),'[]'::jsonb),
 'monthly',coalesce((select jsonb_agg(jsonb_build_object('department',m.department,'month',m.month_key,'total',m.total) order by m.month_key,m.department) from monthly m),'[]'::jsonb),
 'month_stars',coalesce((select jsonb_agg(to_jsonb(m) order by full_name) from monthly_people m where total=(select max(total) from monthly_people)),'[]'::jsonb),
 'month_departments',coalesce((select jsonb_agg(to_jsonb(m) order by department) from monthly_depts m where total=(select max(total) from monthly_depts)),'[]'::jsonb),
 'filters',jsonb_build_object('departments',coalesce((select jsonb_agg(department order by department) from (select department from known_departments) x),'[]'::jsonb),
 'kinds',coalesce((select jsonb_agg(kind order by kind) from (select distinct kind from approved where duplicate_order=1) x),'[]'::jsonb),
 'projects',coalesce((select jsonb_agg(name order by name) from public.school_tags where kind='project'),'[]'::jsonb)),
 'pending_review',case when documentation_private.can_manage() then (select count(*) from achievement_private.candidates where deleted_at is null and review_state is distinct from 'excluded' and (review_state is distinct from 'approved' or reviewed_version is distinct from edit_version)) else null end
 ) into result;
 return result;
end $$;
revoke all on function achievement_private.dashboard(text,integer,text,text,text),achievement_private.report_context(bigint),achievement_private.review_report(bigint,text,integer,text) from public,anon;
grant execute on function achievement_private.dashboard(text,integer,text,text,text),achievement_private.report_context(bigint),achievement_private.review_report(bigint,text,integer,text) to authenticated;
create function public.achievement_dashboard(period text default 'month',year_start integer default 2026,department_filter text default '',kind_filter text default '',project_filter text default '') returns jsonb language sql security invoker set search_path='' as $$select achievement_private.dashboard(period,year_start,department_filter,kind_filter,project_filter)$$;
create function public.achievement_report_context(report_id bigint) returns jsonb language sql security invoker set search_path='' as $$select achievement_private.report_context(report_id)$$;
create function public.review_achievement_report(report_id bigint,decision text,expected_version integer,note text default '') returns jsonb language sql security invoker set search_path='' as $$select achievement_private.review_report(report_id,decision,expected_version,note)$$;
revoke all on function public.achievement_dashboard(text,integer,text,text,text),public.achievement_report_context(bigint),public.review_achievement_report(bigint,text,integer,text) from public,anon;
grant execute on function public.achievement_dashboard(text,integer,text,text,text),public.achievement_report_context(bigint),public.review_achievement_report(bigint,text,integer,text) to authenticated;
