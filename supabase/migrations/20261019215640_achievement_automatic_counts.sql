-- Automatically count complete saved reports; retain explicit administrative exclusions.
-- Does not change report content, status, ownership, files, or existing access policies.
create or replace function achievement_private.report_context(report_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r record;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 if not documentation_private.can_manage() then return jsonb_build_object('can_review',false);end if;
 select * into r from achievement_private.candidates c where c.id=report_id;
 if not found then raise exception 'التقرير غير موجود.';end if;
 return jsonb_build_object('can_review',true,'complete',r.complete,'test_record',r.test_record,'deleted',r.deleted_at is not null,
 'version',r.edit_version,'state',case when r.review_state='excluded' then 'excluded' when r.complete and not r.test_record and r.deleted_at is null then 'automatic' else 'ineligible' end);
end $$;
create or replace function achievement_private.dashboard(period text,year_start integer,department_filter text,kind_filter text,project_filter text) returns jsonb language plpgsql stable security definer set search_path='' as $$
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
 where c.deleted_at is null and c.complete and not c.test_record and c.review_state is distinct from 'excluded'
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
 'pending_review',case when documentation_private.can_manage() then (select count(*) from achievement_private.candidates where deleted_at is null and not complete and not test_record and review_state is distinct from 'excluded') else null end
 ) into result;
 return result;
end $$;
