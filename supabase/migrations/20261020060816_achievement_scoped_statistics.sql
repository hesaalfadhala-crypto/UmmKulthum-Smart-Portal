-- Only sanitized school aggregates, a fixed school top three, self statistics,
-- and explicitly assigned supervisory rosters leave this private function.
-- Existing document/profile/grant rows and their RLS policies are untouched.
create function achievement_private.department_key(value text) returns text language sql immutable security invoker set search_path='' as $$
 select case when btrim(value) in('الاجتماعيات','الاجتماعيات والمواطنة') then 'الاجتماعيات والمواطنة' else nullif(btrim(value),'') end
$$;
revoke all on function achievement_private.department_key(text) from public,anon,authenticated;
create or replace function achievement_private.dashboard(period text,year_start integer,department_filter text,kind_filter text,project_filter text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone 'Asia/Bahrain')::date; ys date; ye date; starts date; ends date; sem text; current_sem text;
 anchor date; prior_month date; full_school boolean; allowed text[]; chosen_department text; result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 if period is null or period not in('week','month','semester1','semester2','year') or year_start is null or year_start not between 2000 and 2100
 or length(coalesce(department_filter,''))>300 or length(coalesce(kind_filter,''))>300 or length(coalesce(project_filter,''))>300 then raise exception 'فلاتر الإحصائيات غير صالحة.';end if;
 full_school:=documentation_private.can_manage();
 -- A display title, a profile department, or a role alone cannot grant supervision.
 select coalesce(array_agg(distinct achievement_private.department_key(g.department)) filter(where achievement_private.department_key(g.department) is not null),'{}') into allowed
 from public.profiles p join public.observation_access g on g.user_id=p.id and g.can_edit
 where p.id=auth.uid() and p.role in('assistant_principal','first_teacher','coordinator')
 and (p.role='assistant_principal' or exists(select 1 from unnest(case when cardinality(p.departments)>0 then p.departments else array[p.department] end) d where achievement_private.department_key(d)=achievement_private.department_key(g.department)));
 chosen_department:=achievement_private.department_key(department_filter);
 if chosen_department is not null and not full_school and not chosen_department=any(allowed) then raise exception 'القسم خارج تكليف المتابعة المعتمد لحسابكِ.' using errcode='42501';end if;
 ys:=make_date(year_start,9,1);ye:=make_date(year_start+1,9,1);
 starts:=case period when 'week' then today-extract(dow from today)::int when 'month' then date_trunc('month',today)::date else ys end;
 ends:=case period when 'week' then starts+7 when 'month' then (starts+interval '1 month')::date else ye end;
 sem:=case period when 'semester1' then 'الفصل الدراسي الأول' when 'semester2' then 'الفصل الدراسي الثاني' else null end;
 current_sem:=coalesce(sem,case when extract(month from least(greatest(today,ys),ye-1))>=9 or extract(month from least(greatest(today,ys),ye-1))=1 then 'الفصل الدراسي الأول' else 'الفصل الدراسي الثاني' end);
 anchor:=date_trunc('month',least(greatest(today,ys),ye-1))::date;prior_month:=(anchor-interval '1 month')::date;
 with ranked_records as (
 select c.*,achievement_private.department_key(c.department) dept_key,row_number() over(partition by c.fingerprint order by c.id) duplicate_order
 from achievement_private.candidates c join public.profiles p on p.id=c.created_by
 where c.deleted_at is null and c.complete and not c.test_record and c.review_state is distinct from 'excluded' and c.activity_date<=today
 ), eligible as (select * from ranked_records where duplicate_order=1),
 year_school as (select * from eligible where academic_year=year_start||'-'||(year_start+1) and activity_date>=ys and activity_date<ye),
 period_school as (select * from year_school where activity_date>=starts and activity_date<ends and (sem is null or semester=sem)),
 -- The public leaderboard is never sliced by department, project, or activity kind.
 school_people as (select created_by,count(*) total from period_school group by created_by),
 school_ranked as (select p.full_name,coalesce(p.department,'') department,n.total,row_number() over(order by n.total desc,p.full_name collate "C",p.id) rank,p.id=auth.uid() is_self from school_people n join public.profiles p on p.id=n.created_by),
 filtered as (select e.* from eligible e where (coalesce(kind_filter,'')='' or e.kind=kind_filter)
 and (coalesce(project_filter,'')='' or exists(select 1 from public.documentation_tags dt join public.school_tags st on st.id=dt.tag_id where dt.documentation_id=e.id and st.kind='project' and st.name=project_filter))),
 annual as (select * from filtered where academic_year=year_start||'-'||(year_start+1) and activity_date>=ys and activity_date<ye),
 selected as (select * from annual where activity_date>=starts and activity_date<ends and (sem is null or semester=sem)),
 known_departments as (
 select achievement_private.department_key(x) department from unnest(array['اللغة العربية','اللغة الإنجليزية','الرياضيات','العلوم','الاجتماعيات والمواطنة','الإرشاد الاجتماعي','مركز مصادر التعلم','تكنولوجيا التعليم','التربية الإسلامية','الحاسوب','التربية الأسرية','التربية الرياضية','المجالات','الإدارة المدرسية','مركز الدعم والتطوير المهني']) x
 union select achievement_private.department_key(d) from public.profiles p cross join lateral unnest(case when cardinality(p.departments)>0 then p.departments else array[p.department] end) d where achievement_private.department_key(d) is not null
 union select dept_key from eligible where dept_key is not null
 ), depts as (select k.department,count(s.id) total from known_departments k left join selected s on s.dept_key=k.department group by k.department),
 growth as (select k.department,count(f.id) filter(where f.activity_date>=anchor and f.activity_date<(anchor+interval '1 month')) current_total,
 count(f.id) filter(where f.activity_date>=prior_month and f.activity_date<anchor) previous_total,
 count(f.id) filter(where f.activity_date>=anchor and f.activity_date<(anchor+interval '1 month'))-count(f.id) filter(where f.activity_date>=prior_month and f.activity_date<anchor) delta
 from known_departments k left join filtered f on f.dept_key=k.department and f.activity_date>=prior_month and f.activity_date<(anchor+interval '1 month') group by k.department),
 authorized_people as (select p.* from public.profiles p where (full_school or exists(select 1 from unnest(case when cardinality(p.departments)>0 then p.departments else array[p.department] end) d where achievement_private.department_key(d)=any(allowed)))
 and (chosen_department is null or exists(select 1 from unnest(case when cardinality(p.departments)>0 then p.departments else array[p.department] end) d where achievement_private.department_key(d)=chosen_department))),
 supervised_people as (select p.id,p.full_name,coalesce(p.department,'') department,coalesce(p.job_title,'') job_title,
 (select count(*) from selected where created_by=p.id) total,
 (select count(*) from annual where created_by=p.id and activity_date>=anchor and activity_date<(anchor+interval '1 month')) month_total,
 (select count(*) from annual where created_by=p.id and semester=current_sem) semester_total,
 (select max(activity_date) from selected where created_by=p.id) last_date
 from authorized_people p),
 monthly as (select dept_key department,to_char(activity_date,'YYYY-MM') month_key,count(*) total from annual group by dept_key,to_char(activity_date,'YYYY-MM'))
 select jsonb_build_object(
 'updated_at',now(),'can_review',full_school,'full_statistics',full_school,'period',period,'start_date',starts,'end_date',ends-1,'semester',sem,
 'totals',jsonb_build_object('reports',(select count(*) from selected),'departments',(select count(*) from depts where total>0),'users',(select count(distinct created_by) from selected),
 'week',(select count(*) from annual where activity_date>=today-extract(dow from today)::int and activity_date<today-extract(dow from today)::int+7),
 'month',(select count(*) from annual where activity_date>=anchor and activity_date<(anchor+interval '1 month')),
 'semester',(select count(*) from annual where semester=current_sem)),
 'departments',coalesce((select jsonb_agg(jsonb_build_object('name',department,'total',total) order by total desc,department) from depts),'[]'::jsonb),
 'participants',coalesce((select jsonb_agg(to_jsonb(p) order by rank) from school_ranked p where rank<=3),'[]'::jsonb),
 'own_total',(select count(*) from selected where created_by=auth.uid()),
 'personal',(select jsonb_build_object('full_name',p.full_name,'department',coalesce(p.department,''),'job_title',coalesce(p.job_title,''),'period_total',(select count(*) from selected where created_by=p.id),
 'year_total',(select count(*) from annual where created_by=p.id),'month_total',(select count(*) from filtered where created_by=p.id and activity_date>=anchor and activity_date<(anchor+interval '1 month')),
 'previous_month_total',(select count(*) from filtered where created_by=p.id and activity_date>=prior_month and activity_date<anchor),
 'current_month',to_char(anchor,'YYYY-MM'),'previous_month',to_char(prior_month,'YYYY-MM')) from public.profiles p where p.id=auth.uid()),
 'own_monthly',coalesce((select jsonb_agg(jsonb_build_object('month',month_key,'total',total) order by month_key) from (select to_char(activity_date,'YYYY-MM') month_key,count(*) total from annual where created_by=auth.uid() group by to_char(activity_date,'YYYY-MM')) x),'[]'::jsonb),
 'monthly',coalesce((select jsonb_agg(jsonb_build_object('department',department,'month',month_key,'total',total) order by month_key,department) from monthly),'[]'::jsonb),
 'month_stars','[]'::jsonb,
 'month_departments',coalesce((select jsonb_agg(jsonb_build_object('department',department,'total',total) order by department) from depts where total>0 and total=(select max(total) from depts)),'[]'::jsonb),
 'department_growth',coalesce((select jsonb_agg(jsonb_build_object('department',department,'current_total',current_total,'previous_total',previous_total,'delta',delta) order by department) from growth where delta>0 and delta=(select max(delta) from growth)),'[]'::jsonb),
 'growth_current_month',to_char(anchor,'YYYY-MM'),'growth_previous_month',to_char(prior_month,'YYYY-MM'),
 'supervision',case when full_school or cardinality(allowed)>0 then jsonb_build_object('full_access',full_school,'departments',case when full_school then (select jsonb_agg(department order by department) from known_departments) else to_jsonb(allowed) end,
 'people',coalesce((select jsonb_agg(jsonb_build_object('full_name',full_name,'department',department,'job_title',job_title,'total',total,'month_total',month_total,'semester_total',semester_total,'last_date',last_date) order by total desc,full_name) from supervised_people),'[]'::jsonb),
 'department_totals',coalesce((select jsonb_agg(jsonb_build_object('department',department,'total',total) order by department) from depts where (full_school or department=any(allowed)) and (chosen_department is null or department=chosen_department)),'[]'::jsonb)) else null end,
 'filters',jsonb_build_object('departments',(select jsonb_agg(department order by department) from known_departments),
 'kinds',coalesce((select jsonb_agg(kind order by kind) from (select distinct kind from eligible) x),'[]'::jsonb),
 'projects',coalesce((select jsonb_agg(name order by name) from public.school_tags where kind='project'),'[]'::jsonb)),
 'pending_review',case when full_school then (select count(*) from achievement_private.candidates where deleted_at is null and not complete and not test_record and review_state is distinct from 'excluded') else null end
 ) into result;
 return result;
end $$;
-- Preserve the existing signed-in-only API and ensure no privileged helper gains a public grant.
revoke all on function achievement_private.dashboard(text,integer,text,text,text) from public,anon;
grant execute on function achievement_private.dashboard(text,integer,text,text,text) to authenticated;
