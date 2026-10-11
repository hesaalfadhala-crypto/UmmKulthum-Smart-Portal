-- Additive weekly planning workflow. Existing accounts, documents and grants are untouched.
create schema weekly_private;
revoke all on schema weekly_private from public, anon;
grant usage on schema weekly_private to authenticated;

create table public.weekly_staff (
 id uuid primary key default gen_random_uuid(), teacher_id uuid unique references public.observation_teachers(id),
 user_id uuid unique references public.profiles(id), full_name text not null check(length(full_name) between 2 and 200),
 department text not null check(length(department) between 2 and 100), role_label text not null default 'معلمة',
 active boolean not null default true, author_enabled boolean not null default false,
 required_by_default boolean not null default false, updated_at timestamptz not null default now()
);
create table public.weekly_periods (
 id uuid primary key default gen_random_uuid(), academic_year text not null check(academic_year ~ '^20[0-9]{2}-20[0-9]{2}$'),
 semester integer not null check(semester in(1,2)), week_number integer not null check(week_number between 1 and 60),
 starts_on date not null check(extract(dow from starts_on)=0), ends_on date not null,
 due_at timestamptz not null, created_by uuid not null references profiles(id), created_at timestamptz not null default now(),
 check(ends_on=starts_on+4), unique(academic_year,semester,week_number)
);
-- Reuse the protected school roster; teacher identities and emails stay out of GitHub.
insert into public.weekly_staff(teacher_id,user_id,full_name,department,role_label,active)
select id,user_id,full_name,department,case position when 'first_teacher' then 'معلمة أولى' when 'coordinator' then 'منسقة' else 'معلمة' end,active
from public.observation_teachers where academic_year='2026-2027';
create table public.weekly_assignments (
 period_id uuid references weekly_periods(id), staff_id uuid references weekly_staff(id), required boolean not null default true,
 assigned_by uuid not null references profiles(id), primary key(period_id,staff_id)
);
create table public.weekly_principal_delegates (
 user_id uuid primary key references profiles(id), granted_by uuid not null references profiles(id),
 reason text not null check(length(trim(reason)) between 5 and 1000), created_at timestamptz not null default now()
);
create table public.weekly_plans (
 id uuid primary key, period_id uuid not null references weekly_periods(id), kind text not null check(kind in('principal','staff')),
 staff_id uuid references weekly_staff(id), created_by uuid not null references profiles(id), owner_name text not null,
 department text not null default '', status text not null default 'draft' check(status in('draft','submitted','approved','needs_revision','published')),
 body jsonb not null default '{"slots":[],"deliveries":[],"notes":""}', file_id uuid,
 version integer not null default 1, submitted_at timestamptz, reviewed_by uuid references profiles(id), reviewer_name text,
 reviewed_at timestamptz, review_note text, published_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((kind='principal' and staff_id is null) or(kind='staff' and staff_id is not null))
);
create unique index weekly_one_principal on weekly_plans(period_id) where kind='principal';
create unique index weekly_one_staff on weekly_plans(period_id,staff_id) where kind='staff';
create index weekly_plans_staff_history on weekly_plans(staff_id,updated_at desc);
create index weekly_plans_period_status on weekly_plans(period_id,status);
create table public.weekly_files (
 id uuid primary key, plan_id uuid not null references weekly_plans(id), path text not null unique,
 original_name text not null, mime_type text not null, uploaded_by uuid not null references profiles(id), uploaded_at timestamptz not null default now()
);
alter table weekly_plans add constraint weekly_current_file foreign key(file_id) references weekly_files(id);
create index weekly_files_plan on weekly_files(plan_id);
create table public.weekly_publications (
 plan_id uuid primary key references weekly_plans(id), period_id uuid not null references weekly_periods(id),
 owner_name text not null, body jsonb not null, file_id uuid references weekly_files(id),
 version integer not null, published_by uuid not null references profiles(id),
 published_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.weekly_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references profiles(id),
 plan_id uuid not null references weekly_plans(id), event text not null, message text not null,
 created_at timestamptz not null default now(), read_at timestamptz
);
create index weekly_notifications_recipient on weekly_notifications(recipient_id,created_at desc);
create table public.weekly_reviews (
 id uuid primary key default gen_random_uuid(), plan_id uuid not null references weekly_plans(id),
 version integer not null, reviewer_id uuid not null references profiles(id), reviewer_name text not null,
 decision text not null, note text not null default '', created_at timestamptz not null default now()
);
create index weekly_reviews_plan on weekly_reviews(plan_id,created_at desc);
create table weekly_private.operations (id uuid primary key, actor uuid not null, input jsonb not null, result jsonb not null);
alter table weekly_private.operations enable row level security;

create function weekly_private.registered() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid())
$$;
create function weekly_private.full_access() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and school_access='all' and role in('principal','assistant_principal'))
$$;
create function weekly_private.principal_editor() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (exists(select 1 from public.profiles where id=auth.uid() and role='principal' and school_access='all') or exists(select 1 from public.weekly_principal_delegates where user_id=auth.uid()))
$$;
create function weekly_private.reviews_department(dept text) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.full_access() or (auth.uid() is not null and exists(select 1 from public.profiles p join public.observation_access a on a.user_id=p.id where p.id=auth.uid() and p.role in('assistant_principal','first_teacher','coordinator') and a.department=dept and a.can_edit))
$$;
create function weekly_private.read_plan(plan_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(select 1 from public.weekly_plans p left join public.weekly_staff s on s.id=p.staff_id where p.id=plan_uuid and
 ((p.kind='principal' and (weekly_private.full_access() or weekly_private.principal_editor())) or
 (p.kind='staff' and (s.user_id=auth.uid() or weekly_private.reviews_department(p.department)))))
$$;
create function weekly_private.edit_plan(plan_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(select 1 from public.weekly_plans p left join public.weekly_staff s on s.id=p.staff_id where p.id=plan_uuid and
 ((p.kind='principal' and weekly_private.principal_editor()) or(p.kind='staff' and s.user_id=auth.uid() and s.active and (s.author_enabled or exists(select 1 from public.weekly_assignments a where a.staff_id=s.id and a.period_id=p.period_id and a.required)))))
$$;
create function weekly_private.read_file(file_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(select 1 from public.weekly_files f where f.id=file_uuid and
 (weekly_private.read_plan(f.plan_id) or exists(select 1 from public.weekly_publications pp where pp.file_id=f.id)))
$$;
create function weekly_private.file_access(object_name text, editing boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare parts text[];
begin
 if not weekly_private.registered() then return false; end if;
 parts:=string_to_array(object_name,'/');
 if array_length(parts,1)<>3 or parts[1]!~'^[a-f0-9-]{36}$' or parts[2]!~'^[a-f0-9-]{36}$' or parts[3]!~'^[a-f0-9-]{36}\.(pdf|xlsx)$' then return false; end if;
 if editing then return parts[1]=auth.uid()::text and weekly_private.edit_plan(parts[2]::uuid) and not exists(select 1 from public.weekly_files where path=object_name); end if;
 return exists(select 1 from public.weekly_files f where f.path=object_name and weekly_private.read_file(f.id)) or(parts[1]=auth.uid()::text and weekly_private.edit_plan(parts[2]::uuid));
exception when invalid_text_representation then return false;
end $$;

alter table weekly_staff enable row level security;
alter table weekly_periods enable row level security;
alter table weekly_assignments enable row level security;
alter table weekly_principal_delegates enable row level security;
alter table weekly_plans enable row level security;
alter table weekly_files enable row level security;
alter table weekly_publications enable row level security;
alter table weekly_notifications enable row level security;
alter table weekly_reviews enable row level security;
revoke all on weekly_staff,weekly_periods,weekly_assignments,weekly_principal_delegates,weekly_plans,weekly_files,weekly_publications,weekly_notifications,weekly_reviews from anon,authenticated;
grant select on weekly_staff,weekly_periods,weekly_assignments,weekly_principal_delegates,weekly_plans,weekly_files,weekly_publications,weekly_notifications,weekly_reviews to authenticated;
grant update(read_at) on weekly_notifications to authenticated;
create policy weekly_staff_read on weekly_staff for select to authenticated using(user_id=auth.uid() or weekly_private.reviews_department(department));
create policy weekly_periods_read on weekly_periods for select to authenticated using(weekly_private.registered());
create policy weekly_assignments_read on weekly_assignments for select to authenticated using(exists(select 1 from weekly_staff s where s.id=staff_id));
create policy weekly_delegates_read on weekly_principal_delegates for select to authenticated using(user_id=auth.uid() or weekly_private.full_access());
create policy weekly_plans_read on weekly_plans for select to authenticated using(weekly_private.read_plan(id));
create policy weekly_files_read on weekly_files for select to authenticated using(weekly_private.read_file(id));
create policy weekly_published_read on weekly_publications for select to authenticated using(weekly_private.registered());
create policy weekly_notifications_read on weekly_notifications for select to authenticated using(recipient_id=auth.uid());
create policy weekly_notifications_seen on weekly_notifications for update to authenticated using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
create policy weekly_reviews_read on weekly_reviews for select to authenticated using(weekly_private.read_plan(plan_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('weekly-plan-files','weekly-plan-files',false,15728640,array['application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy weekly_storage_read on storage.objects for select to authenticated using(bucket_id='weekly-plan-files' and weekly_private.file_access(name));
create policy weekly_storage_insert on storage.objects for insert to authenticated with check(bucket_id='weekly-plan-files' and weekly_private.file_access(name,true));
create policy weekly_storage_delete_unused on storage.objects for delete to authenticated using(bucket_id='weekly-plan-files' and weekly_private.file_access(name,true));

create function weekly_private.previous_operation(op uuid,arg jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare prior weekly_private.operations;
begin
 if not weekly_private.registered() then raise exception 'يرجى تسجيل الدخول بحساب المدرسة.' using errcode='42501'; end if;
 if op is null then raise exception 'معرف محاولة الحفظ مطلوب.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(op::text,0));
 select * into prior from weekly_private.operations where id=op;
 if found then
  if prior.actor<>auth.uid() or prior.input<>arg then raise exception 'معرف الحفظ مستخدم لبيانات مختلفة.' using errcode='22023'; end if;
  return prior.result;
 end if;
 return null;
end $$;
create function weekly_private.validate_body(b jsonb) returns void language plpgsql immutable set search_path='' as $$
declare s jsonb; keys text[]; d jsonb;
begin
 if b is null or jsonb_typeof(b)<>'object' or b-ARRAY['slots','deliveries','notes']<>'{}'::jsonb or
 jsonb_typeof(b->'slots') is distinct from 'array' or jsonb_typeof(b->'deliveries') is distinct from 'array' or jsonb_typeof(b->'notes') is distinct from 'string' or length(b->>'notes')>5000 or jsonb_array_length(b->'slots')>50 or jsonb_array_length(b->'deliveries')>60 then raise exception 'بيانات جدول الخطة غير صالحة.'; end if;
 for s in select * from jsonb_array_elements(b->'slots') loop
  if jsonb_typeof(s)<>'object' or s-ARRAY['day','period','text','category']<>'{}'::jsonb or coalesce(s->>'day','')!~'^[0-4]$' or coalesce(s->>'period','') not in('morning','1','2','3','break','4','5','6','7','emergency') or coalesce(s->>'category','') not in('visit','meeting','official','admin','none') or jsonb_typeof(s->'text') is distinct from 'string' or length(s->>'text')>2500 then raise exception 'إحدى مهام الخطة غير صالحة.'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(b->'slots') slot_value group by slot_value->>'day',slot_value->>'period' having count(*)>1) then raise exception 'الحصة مكررة في اليوم نفسه.'; end if;
 for d in select * from jsonb_array_elements(b->'deliveries') loop
  if jsonb_typeof(d)<>'object' or d-ARRAY['task','responsible','due']<>'{}'::jsonb or jsonb_typeof(d->'task') is distinct from 'string' or jsonb_typeof(d->'responsible') is distinct from 'string' or length(d->>'task') not between 1 and 1000 or length(d->>'responsible') not between 1 and 300 or coalesce(d->>'due','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'بيانات التسليم غير مكتملة.'; end if;
  perform (d->>'due')::date;
 end loop;
end $$;

create function weekly_private.save_plan(payload jsonb,expected_version integer,operation_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare arg jsonb:=jsonb_build_object('payload',payload,'version',expected_version,'action','save'); result jsonb; p public.weekly_plans; s public.weekly_staff; w public.weekly_periods; pid uuid; k text; b jsonb; desired text; fid uuid; uid uuid:=auth.uid(); author text;
begin
 result:=weekly_private.previous_operation(operation_id,arg); if result is not null then return result; end if;
 if payload-ARRAY['id','period_id','kind','staff_id','body','file_id','submit']<>'{}'::jsonb then raise exception 'حقول الخطة غير صالحة.'; end if;
 pid:=(payload->>'id')::uuid; k:=payload->>'kind'; b:=payload->'body'; fid:=nullif(payload->>'file_id','')::uuid;
 perform weekly_private.validate_body(b);
 select * into w from public.weekly_periods where id=(payload->>'period_id')::uuid;
 if not found then raise exception 'اختاري أسبوعًا معتمدًا من إدارة المدرسة.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,1));
 select * into p from public.weekly_plans where id=pid for update;
 if found then
  if not weekly_private.edit_plan(pid) then raise exception 'ليس لديكِ صلاحية تعديل هذه الخطة.' using errcode='42501'; end if;
  if expected_version is distinct from p.version then raise exception 'تم تعديل الخطة من جلسة أخرى. أعيدي تحميلها.' using errcode='40001'; end if;
  if k<>p.kind or w.id<>p.period_id or nullif(payload->>'staff_id','')::uuid is distinct from p.staff_id then raise exception 'لا يمكن تغيير صاحبة الخطة أو الأسبوع بعد إنشائها.'; end if;
 else
  if expected_version<>0 or pid is null then raise exception 'معرف الخطة الجديدة غير صالح.'; end if;
  if k='principal' then
   if not weekly_private.principal_editor() then raise exception 'إنشاء خطة المديرة يحتاج صلاحية المديرة أو تفويضًا رسميًا.' using errcode='42501'; end if;
   select full_name into author from public.profiles where role='principal' and school_access='all' order by id limit 1;
  elsif k='staff' then
   select * into s from public.weekly_staff where id=(payload->>'staff_id')::uuid and user_id=uid and active and (author_enabled or exists(select 1 from public.weekly_assignments a where a.staff_id=weekly_staff.id and a.period_id=w.id and a.required));
   if not found then raise exception 'حسابكِ غير مخول بإدخال خطة. تواصلي مع الإدارة لربط الاسم والتكليف.' using errcode='42501'; end if;
   author:=s.full_name;
  else raise exception 'نوع الخطة غير صالح.'; end if;
  insert into public.weekly_plans(id,period_id,kind,staff_id,created_by,owner_name,department,body) values(pid,w.id,k,s.id,uid,author,coalesce(s.department,''),b) returning * into p;
 end if;
 if fid is not null and not exists(select 1 from public.weekly_files where id=fid and plan_id=pid) then raise exception 'الملف غير محفوظ لهذه الخطة.'; end if;
 if k='principal' and fid is not null and not exists(select 1 from public.weekly_files where id=fid and mime_type='application/pdf') then raise exception 'خطة المديرة الجاهزة يجب أن تكون PDF.'; end if;
 desired:=case when k='staff' and coalesce((payload->>'submit')::boolean,false) then 'submitted' else 'draft' end;
 if desired='submitted' and fid is null and not exists(select 1 from jsonb_array_elements(b->'slots') x where length(trim(x->>'text'))>0) then raise exception 'أدخلي المهام أو ارفعي ملف الخطة قبل تقديمها.'; end if;
 update public.weekly_plans set body=b,file_id=fid,status=desired,version=case when expected_version=0 then 1 else version+1 end,updated_at=now(),submitted_at=case when desired='submitted' then coalesce(submitted_at,now()) else submitted_at end,reviewed_by=null,reviewer_name=null,reviewed_at=null,review_note=null where id=pid returning * into p;
 if desired='submitted' then
  insert into public.weekly_notifications(recipient_id,plan_id,event,message)
  select x.id,pid,'submitted','خطة جديدة للمراجعة: '||p.owner_name||' — الأسبوع '||w.week_number from public.profiles x where
  (x.role in('principal','assistant_principal') and x.school_access='all') or (x.role in('assistant_principal','first_teacher','coordinator') and x.id<>uid and exists(select 1 from public.observation_access a where a.user_id=x.id and a.department=p.department and a.can_edit));
 end if;
 result:=jsonb_build_object('id',pid,'version',p.version,'status',p.status);
 insert into weekly_private.operations values(operation_id,uid,arg,result); return result;
end $$;

create function weekly_private.attach_file(plan_uuid uuid,file_uuid uuid,object_path text,original_name text,mime_type text,operation_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare arg jsonb:=jsonb_build_object('action','file','plan',plan_uuid,'file',file_uuid,'path',object_path,'name',original_name,'mime',mime_type); result jsonb; ext text;
begin
 result:=weekly_private.previous_operation(operation_id,arg);if result is not null then return result;end if;
 if not weekly_private.edit_plan(plan_uuid) then raise exception 'ليس لديكِ صلاحية إرفاق ملف.' using errcode='42501'; end if;
 ext:=case mime_type when 'application/pdf' then 'pdf' when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then 'xlsx' else null end;
 if ext is null or object_path<>auth.uid()::text||'/'||plan_uuid::text||'/'||file_uuid::text||'.'||ext or length(original_name) not between 1 and 250 or not exists(select 1 from storage.objects o where bucket_id='weekly-plan-files' and name=object_path and coalesce(o.owner_id,o.owner::text)=auth.uid()::text) then raise exception 'الملف المرفوع غير مكتمل أو غير مملوك للحساب.'; end if;
 if ext='xlsx' and exists(select 1 from public.weekly_plans where id=plan_uuid and kind='principal') then raise exception 'خطة المديرة الجاهزة يجب أن تكون PDF.'; end if;
 insert into public.weekly_files(id,plan_id,path,original_name,mime_type,uploaded_by) values(file_uuid,plan_uuid,object_path,original_name,mime_type,auth.uid());
 result:=jsonb_build_object('id',file_uuid);insert into weekly_private.operations values(operation_id,auth.uid(),arg,result);return result;
end $$;

create function weekly_private.decide_plan(plan_uuid uuid,decision text,note text,expected_version integer,operation_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.weekly_plans; w public.weekly_periods; arg jsonb:=jsonb_build_object('action','decision','plan',plan_uuid,'decision',decision,'note',note,'version',expected_version); result jsonb; reviewer text; owner uuid;
begin
 result:=weekly_private.previous_operation(operation_id,arg);if result is not null then return result;end if;
 select * into p from public.weekly_plans where id=plan_uuid for update;
 if not found then raise exception 'الخطة غير متاحة.' using errcode='42501';end if;
 if p.version is distinct from expected_version then raise exception 'تم تعديل الخطة. أعيدي تحميلها قبل اتخاذ القرار.' using errcode='40001';end if;
 select * into w from public.weekly_periods where id=p.period_id;
 select full_name into reviewer from public.profiles where id=auth.uid();
 if decision='published' then
  if p.kind<>'principal' or not weekly_private.principal_editor() then raise exception 'نشر خطة المديرة يحتاج تفويضًا رسميًا.' using errcode='42501';end if;
  if p.status not in('draft','published') then raise exception 'حالة الخطة لا تسمح بالنشر.';end if;
  if p.file_id is null and not exists(select 1 from jsonb_array_elements(p.body->'slots') x where length(trim(x->>'text'))>0) then raise exception 'الخطة فارغة. أدخلي المهام أو ارفعي PDF.';end if;
  insert into public.weekly_publications(plan_id,period_id,owner_name,body,file_id,version,published_by) values(p.id,p.period_id,p.owner_name,p.body,p.file_id,p.version+1,auth.uid()) on conflict(plan_id) do update set body=excluded.body,file_id=excluded.file_id,version=excluded.version,published_by=excluded.published_by,updated_at=now();
  insert into public.weekly_notifications(recipient_id,plan_id,event,message) select id,p.id,'published','نشر أو تحديث خطة مديرة المدرسة — الأسبوع '||w.week_number from public.profiles;
 elsif decision in('approved','needs_revision') then
  if p.kind<>'staff' or not weekly_private.reviews_department(p.department) then raise exception 'الخطة خارج صلاحيات المراجعة.' using errcode='42501';end if;
  if p.status<>'submitted' then raise exception 'تُراجع الخطط المقدمة للمراجعة فقط.';end if;
  if exists(select 1 from public.weekly_staff where id=p.staff_id and user_id=auth.uid()) then raise exception 'مراجعة خطتكِ واعتمادها تكون بواسطة قيادة مخولة أخرى.' using errcode='42501';end if;
  if decision='needs_revision' and length(trim(coalesce(note,'')))<5 then raise exception 'اكتبي ملاحظات التعديل المطلوبة.';end if;
  select user_id into owner from public.weekly_staff where id=p.staff_id;
  if owner is not null then insert into public.weekly_notifications(recipient_id,plan_id,event,message) values(owner,p.id,decision,case when decision='approved' then 'تم اعتماد خطتكِ' else 'خطتكِ تحتاج تعديلًا' end||' — الأسبوع '||w.week_number);end if;
 else raise exception 'قرار المراجعة غير صالح.';end if;
 if length(coalesce(note,''))>5000 then raise exception 'ملاحظات المراجعة طويلة جدًا.';end if;
 update public.weekly_plans set status=decision,version=version+1,updated_at=now(),reviewed_by=auth.uid(),reviewer_name=reviewer,reviewed_at=now(),review_note=note,published_at=case when decision='published' then now() else published_at end where id=p.id returning * into p;
 insert into public.weekly_reviews(plan_id,version,reviewer_id,reviewer_name,decision,note) values(p.id,p.version,auth.uid(),reviewer,decision,coalesce(note,''));
 result:=jsonb_build_object('id',p.id,'version',p.version,'status',p.status);insert into weekly_private.operations values(operation_id,auth.uid(),arg,result);return result;
end $$;

create function weekly_private.configure(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare action text:=payload->>'action'; sid uuid; uid uuid; p public.weekly_plans; rowid uuid; item jsonb; starts date; ends date; due timestamptz; yr text; n integer; sem integer;
begin
 if not weekly_private.full_access() then raise exception 'إدارة الأسابيع والتكليفات متاحة للمديرة وللمديرة المساعدة المخولة.' using errcode='42501';end if;
 if action='staff' then
  sid:=(payload->>'id')::uuid;uid:=nullif(payload->>'user_id','')::uuid;
  if not exists(select 1 from public.weekly_staff where id=sid) then raise exception 'الاسم غير موجود في كشف الموظفات.';end if;
  if uid is not null and not exists(select 1 from public.profiles pr join auth.users au on au.id=pr.id where pr.id=uid and au.email_confirmed_at is not null) then raise exception 'الحساب غير موجود أو غير موثق.';end if;
  if exists(select 1 from public.weekly_plans where staff_id=sid) and uid is distinct from(select user_id from public.weekly_staff where id=sid) then raise exception 'للاسم خطط محفوظة؛ لا يمكن تبديل حسابه من هذه الشاشة.';end if;
  update public.weekly_staff set user_id=uid,author_enabled=coalesce((payload->>'author_enabled')::boolean,false),required_by_default=coalesce((payload->>'required_by_default')::boolean,false),updated_at=now() where id=sid;
  return jsonb_build_object('id',sid);
 elsif action='period' then
  yr:=payload->>'academic_year';sem:=(payload->>'semester')::integer;n:=(payload->>'week_number')::integer;starts:=(payload->>'starts_on')::date;ends:=starts+4;due:=(payload->>'due_at')::timestamptz;
  if due is null then raise exception 'موعد التسليم مطلوب.';end if;
  if jsonb_typeof(payload->'staff_ids') is distinct from 'array' then raise exception 'اختاري الفئات المكلفة.';end if;
  select id into rowid from public.weekly_periods where academic_year=yr and semester=sem and week_number=n;
  if rowid is null then
   insert into public.weekly_periods(academic_year,semester,week_number,starts_on,ends_on,due_at,created_by) values(yr,sem,n,starts,ends,due,auth.uid()) returning id into rowid;
  else
   if exists(select 1 from public.weekly_plans where period_id=rowid) and starts is distinct from(select starts_on from public.weekly_periods where id=rowid) then raise exception 'للأسبوع خطط محفوظة؛ لا يمكن تغيير فترة الأسبوع.';end if;
   update public.weekly_periods set starts_on=starts,ends_on=ends,due_at=due where id=rowid;
  end if;
  if exists(select 1 from jsonb_array_elements_text(payload->'staff_ids') x where not exists(select 1 from public.weekly_staff s where s.id=x::uuid and s.active)) then raise exception 'إحدى الموظفات المختارات غير متاحة.';end if;
  update public.weekly_assignments set required=false where period_id=rowid;
  insert into public.weekly_assignments(period_id,staff_id,required,assigned_by) select rowid,x::uuid,true,auth.uid() from jsonb_array_elements_text(payload->'staff_ids') x on conflict(period_id,staff_id) do update set required=true,assigned_by=auth.uid();
  return jsonb_build_object('id',rowid);
 elsif action='delegate' then
  if not exists(select 1 from public.profiles where id=auth.uid() and role='principal') then raise exception 'التفويض الرسمي من حساب المديرة فقط.' using errcode='42501';end if;
  uid:=(payload->>'user_id')::uuid;
  if not exists(select 1 from public.profiles where id=uid) then raise exception 'الحساب غير موجود.';end if;
  if coalesce((payload->>'enabled')::boolean,false) then insert into public.weekly_principal_delegates(user_id,granted_by,reason) values(uid,auth.uid(),payload->>'reason') on conflict(user_id) do update set reason=excluded.reason,granted_by=excluded.granted_by,created_at=now();
  else delete from public.weekly_principal_delegates where user_id=uid;end if;
  return jsonb_build_object('id',uid);
 else raise exception 'الإعداد المطلوب غير صالح.';end if;
end $$;

create function weekly_private.accounts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not weekly_private.full_access() then raise exception 'قائمة ربط الحسابات للإدارة المخولة فقط.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',u.email,'role',p.role) order by p.full_name) from public.profiles p join auth.users u on u.id=p.id where u.email_confirmed_at is not null),'[]');
end $$;
create function weekly_private.context() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not weekly_private.registered() then raise exception 'يرجى تسجيل الدخول بحساب المدرسة.' using errcode='42501';end if;
 return jsonb_build_object('full_access',weekly_private.full_access(),'principal_editor',weekly_private.principal_editor(),'reviewer',weekly_private.full_access() or exists(select 1 from public.profiles p join public.observation_access a on a.user_id=p.id where p.id=auth.uid() and p.role in('assistant_principal','first_teacher','coordinator') and a.can_edit),'user_id',auth.uid(),'profile',(select jsonb_build_object('full_name',full_name,'role',role) from public.profiles where id=auth.uid()));
end $$;

-- Invoker API wrappers. All elevated work and ownership checks live in the unexposed schema.
create function public.save_weekly_plan(payload jsonb,expected_version integer,operation_id uuid) returns jsonb language sql security invoker set search_path='' as $$select weekly_private.save_plan(payload,expected_version,operation_id)$$;
create function public.attach_weekly_file(plan_uuid uuid,file_uuid uuid,object_path text,original_name text,mime_type text,operation_id uuid) returns jsonb language sql security invoker set search_path='' as $$select weekly_private.attach_file(plan_uuid,file_uuid,object_path,original_name,mime_type,operation_id)$$;
create function public.decide_weekly_plan(plan_uuid uuid,decision text,note text,expected_version integer,operation_id uuid) returns jsonb language sql security invoker set search_path='' as $$select weekly_private.decide_plan(plan_uuid,decision,note,expected_version,operation_id)$$;
create function public.configure_weekly_plans(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select weekly_private.configure(payload)$$;
create function public.weekly_accounts() returns jsonb language sql security invoker set search_path='' as $$select weekly_private.accounts()$$;
create function public.weekly_context() returns jsonb language sql security invoker set search_path='' as $$select weekly_private.context()$$;

revoke all on all functions in schema weekly_private from public,anon,authenticated;
grant execute on function weekly_private.registered(),weekly_private.full_access(),weekly_private.principal_editor(),weekly_private.reviews_department(text),weekly_private.read_plan(uuid),weekly_private.edit_plan(uuid),weekly_private.read_file(uuid),weekly_private.file_access(text,boolean),weekly_private.save_plan(jsonb,integer,uuid),weekly_private.attach_file(uuid,uuid,text,text,text,uuid),weekly_private.decide_plan(uuid,text,text,integer,uuid),weekly_private.configure(jsonb),weekly_private.accounts(),weekly_private.context() to authenticated;
revoke all on function public.save_weekly_plan(jsonb,integer,uuid),public.attach_weekly_file(uuid,uuid,text,text,text,uuid),public.decide_weekly_plan(uuid,text,text,integer,uuid),public.configure_weekly_plans(jsonb),public.weekly_accounts(),public.weekly_context() from public,anon;
grant execute on function public.save_weekly_plan(jsonb,integer,uuid),public.attach_weekly_file(uuid,uuid,text,text,text,uuid),public.decide_weekly_plan(uuid,text,text,integer,uuid),public.configure_weekly_plans(jsonb),public.weekly_accounts(),public.weekly_context() to authenticated;
