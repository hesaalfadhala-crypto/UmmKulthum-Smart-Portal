-- Reviewed activation requires school-owner approval; verified coordinator grants are a private step.
-- Additive only: workshop reports stay in the original archive, with its private images.
begin;
create schema support_private;
revoke all on schema support_private from public,anon;
grant usage on schema support_private to authenticated;
-- Private pending grants bind only to an exact verified Auth email, never a display name or user_metadata.
create table support_private.authorized_emails (
 email text primary key check(email=lower(btrim(email)) and email like '%@moe.bh'),
 permission text not null check(permission in ('manage','reports')),
 granted_at timestamptz not null default now()
);
alter table support_private.authorized_emails enable row level security;
revoke all on support_private.authorized_emails from public,anon,authenticated;
create table public.support_center_access (
 user_id uuid primary key references auth.users(id), permission text not null check(permission in ('manage','reports')),
 granted_at timestamptz not null default now()
);
create table public.support_requests (
 id uuid primary key default gen_random_uuid(), created_by uuid not null references auth.users(id), creator_name text not null,
 request_id uuid not null, unique(created_by,request_id), kind text not null check(kind in ('need','proposal','booking')),
 title text not null check(length(btrim(title)) between 1 and 300), department text not null default '',
 audience text not null check(audience in ('teachers','admins','students')), priority text not null default 'normal' check(priority in ('low','normal','high')),
 details text not null default '' check(length(details)<=6000), presenter text not null default '', location text not null default 'مركز الدعم',
 requested_start timestamptz, requested_end timestamptz, submission jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','declined','cancelled','completed')),
 review_note text not null default '' check(length(review_note)<=4000), reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(kind='need' or requested_start is not null and requested_end is not null and requested_end>requested_start),
 check(kind<>'need' or requested_start is null and requested_end is null)
);
create index support_requests_owner_date on public.support_requests(created_by,created_at,id);
create index support_requests_review_queue on public.support_requests(status,kind,created_at);
create index support_requests_reserved on public.support_requests(requested_start,requested_end) where kind='booking' and status='approved';
create table public.support_programs (
 id uuid primary key default gen_random_uuid(), source_request_id uuid not null unique references public.support_requests(id),
 title text not null, presenter text not null, audience text not null, objectives text not null default '', location text not null,
 starts_at timestamptz not null, ends_at timestamptz not null, status text not null default 'planned' check(status in ('planned','completed','cancelled')),
 created_at timestamptz not null default now(), check(ends_at>starts_at)
);
create index support_programs_calendar on public.support_programs(starts_at,ends_at,status);
alter table public.documentations add column support_program_id uuid references public.support_programs(id),
 add column training_beneficiaries integer check(training_beneficiaries between 0 and 10000);
create index documentation_support_program on public.documentations(support_program_id) where support_program_id is not null;
create index documentation_training_date on public.documentations(activity_date,id) where activity_type='ورشة تدريبية';
create table public.support_impacts (
 id uuid primary key default gen_random_uuid(), created_by uuid not null references auth.users(id), creator_name text not null,
 request_id uuid not null, unique(created_by,request_id), program_id uuid references public.support_programs(id), documentation_id bigint references public.documentations(id),
 applied_on date not null, application text not null check(length(btrim(application)) between 1 and 6000),
 evidence text not null default '' check(length(evidence)<=6000), followup text not null default '' check(length(followup)<=6000),
 before_level smallint check(before_level between 1 and 5), after_level smallint check(after_level between 1 and 5), submission jsonb not null,
 created_at timestamptz not null default now(), check(num_nonnulls(program_id,documentation_id)=1), check((before_level is null)=(after_level is null))
);
create index support_impacts_owner_date on public.support_impacts(created_by,created_at,id);
create index support_impacts_program on public.support_impacts(program_id) where program_id is not null;
create index support_impacts_documentation on public.support_impacts(documentation_id) where documentation_id is not null;
create function support_private.member() returns boolean language sql stable set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=(select auth.uid()))
$$;
create function support_private.manager() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p where p.id=auth.uid() and
 ((p.role in ('principal','assistant_principal') and p.school_access='all') or exists(select 1 from public.support_center_access a where a.user_id=p.id and a.permission='manage') or exists(select 1 from support_private.authorized_emails a join auth.users u on u.id=p.id where lower(u.email)=a.email and u.email_confirmed_at is not null and a.permission='manage')))
$$;
create function support_private.reports_reader() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p where p.id=auth.uid() and
 ((p.role in ('principal','assistant_principal') and p.school_access='all') or exists(select 1 from public.support_center_access a where a.user_id=p.id and a.permission in ('manage','reports')) or exists(select 1 from support_private.authorized_emails a join auth.users u on u.id=p.id where lower(u.email)=a.email and u.email_confirmed_at is not null and a.permission in ('manage','reports'))))
$$;
alter table public.support_center_access enable row level security;
alter table public.support_requests enable row level security;
alter table public.support_programs enable row level security;
alter table public.support_impacts enable row level security;
revoke all on public.support_center_access,public.support_requests,public.support_programs,public.support_impacts from public,anon,authenticated;
grant select on public.support_center_access,public.support_requests,public.support_programs,public.support_impacts to authenticated;
create policy support_access_self on public.support_center_access for select to authenticated using(user_id=(select auth.uid()));
create policy support_requests_read on public.support_requests for select to authenticated using((select support_private.member()) and (created_by=(select auth.uid()) or (select support_private.manager())));
create policy support_programs_read on public.support_programs for select to authenticated using((select support_private.member()));
create policy support_impacts_read on public.support_impacts for select to authenticated using((select support_private.member()) and (created_by=(select auth.uid()) or (select support_private.reports_reader())));
-- Coordinators receive only workshop reports. Existing owner/leadership policies remain intact.
create policy support_workshop_reports_read on public.documentations for select to authenticated
using(coalesce(activity_type,nullif(details->>'type',''))='ورشة تدريبية' and (select support_private.reports_reader()));
-- Existing Storage SELECT uses documentation RLS; workshop images inherit this exact boundary.
create function support_private.validate_documentation() returns trigger language plpgsql set search_path='' as $$
begin
 if coalesce(new.activity_type,nullif(new.details->>'type',''))='ورشة تدريبية' then
  if not support_private.member() then raise exception 'يلزم حساب مدرسة معتمد' using errcode='42501';end if;
  if nullif(new.details->>'centerProgramId','') is not null then
   if new.support_program_id is not null and new.support_program_id<> (new.details->>'centerProgramId')::uuid then raise exception 'البرنامج المرتبط غير متطابق';end if;
   new.support_program_id:=(new.details->>'centerProgramId')::uuid;
  end if;
  if nullif(new.details->>'trainingBeneficiaries','') is not null then
   if new.training_beneficiaries is not null and new.training_beneficiaries<>(new.details->>'trainingBeneficiaries')::integer then raise exception 'عدد المستفيدات غير متطابق';end if;
   new.training_beneficiaries:=(new.details->>'trainingBeneficiaries')::integer;
  end if;
  if new.support_program_id is not null and not exists(select 1 from public.support_programs p where p.id=new.support_program_id and p.status in ('planned','completed')) then raise exception 'البرنامج غير متاح للتوثيق';end if;
 else
  if new.support_program_id is not null or new.training_beneficiaries is not null then raise exception 'ربط المركز متاح لتوثيق الورش فقط';end if;
 end if;
 return new;
end $$;
create trigger support_documentation_fields before insert or update of activity_type,details,support_program_id,training_beneficiaries on public.documentations for each row execute function support_private.validate_documentation();
create function support_private.save_request(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); req uuid:=(payload->>'request_id')::uuid; p jsonb:=payload-'request_id'; old public.support_requests; start_at timestamptz; end_at timestamptz; rid uuid;
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول بحساب المدرسة' using errcode='42501';end if;
 if req is null or jsonb_typeof(payload)<>'object' or p-array['kind','title','department','audience','priority','details','presenter','location','date','from','to']<>'{}'::jsonb then raise exception 'بيانات الطلب غير صالحة';end if;
 if payload->>'kind' is null or payload->>'kind' not in ('need','proposal','booking') then raise exception 'نوع الطلب غير صالح';end if;
 if length(coalesce(payload->>'title','')) not between 1 and 300 or btrim(payload->>'title')='' or length(coalesce(payload->>'department',''))>180 or length(coalesce(payload->>'presenter',''))>180 or length(coalesce(payload->>'location',''))>300 then raise exception 'راجعي عنوان الطلب وبياناته';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));
 select * into old from public.support_requests where created_by=uid and request_id=req;
 if old.id is not null then
  if old.submission<>p then raise exception 'هذه المحاولة محفوظة ببيانات مختلفة. استرجعيها قبل بدء طلب جديد';end if;
  return jsonb_build_object('id',old.id,'status',old.status,'recovered',true);
 end if;
 if payload->>'kind'<>'need' then
  start_at:=((payload->>'date')||' '||(payload->>'from'))::timestamp at time zone 'Asia/Bahrain';
  end_at:=((payload->>'date')||' '||(payload->>'to'))::timestamp at time zone 'Asia/Bahrain';
  if start_at is null or end_at is null or end_at<=start_at or start_at<now() then raise exception 'اختاري موعدًا قادمًا، ونهاية بعد البداية';end if;
 end if;
 insert into public.support_requests(created_by,creator_name,request_id,kind,title,department,audience,priority,details,presenter,location,requested_start,requested_end,submission)
 values(uid,(select full_name from public.profiles where id=uid),req,payload->>'kind',payload->>'title',coalesce(payload->>'department',''),coalesce(payload->>'audience','teachers'),coalesce(payload->>'priority','normal'),coalesce(payload->>'details',''),coalesce(nullif(payload->>'presenter',''),(select full_name from public.profiles where id=uid)),coalesce(nullif(payload->>'location',''),'مركز الدعم'),start_at,end_at,p) returning id into rid;
 return jsonb_build_object('id',rid,'status','pending','recovered',false);
end $$;
create function support_private.review_request(request_uuid uuid,new_status text,note text,expected_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); old public.support_requests; mgr boolean:=support_private.manager(); pid uuid;
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول' using errcode='42501';end if;
 -- Serialize approvals across bookings and workshop proposals for the same center.
 perform pg_advisory_xact_lock(hashtextextended('ummkulthum-support-center-calendar',0));
 select * into old from public.support_requests where id=request_uuid for update;
 if old.id is null or (not mgr and old.created_by<>uid) then raise exception 'الطلب غير متاح لحسابكِ' using errcode='42501';end if;
 if expected_version is null or expected_version<>old.version then raise exception 'تم تحديث الطلب. حدّثي القائمة قبل المراجعة' using errcode='40001';end if;
 if not mgr and (new_status<>'cancelled' or old.status not in ('pending','approved') or old.requested_start<=now()) then raise exception 'لا تملكين صلاحية لهذا الإجراء' using errcode='42501';end if;
 if new_status is null or new_status not in ('approved','declined','cancelled','completed') or length(coalesce(note,''))>4000 then raise exception 'حالة المراجعة غير صالحة';end if;
 if old.status in ('declined','cancelled','completed') or old.status='approved' and new_status not in ('cancelled','completed') or old.status='pending' and new_status='completed' then raise exception 'هذا الانتقال غير متاح لحالة الطلب';end if;
 if new_status='approved' and old.kind<>'need' then
  if old.requested_start<now() then raise exception 'الموعد مضى. اطلبي موعدًا جديدًا';end if;
  if exists(select 1 from public.support_requests b where b.id<>old.id and b.kind='booking' and b.status='approved' and b.requested_start<old.requested_end and b.requested_end>old.requested_start)
   or exists(select 1 from public.support_programs p where p.source_request_id<>old.id and p.status='planned' and p.starts_at<old.requested_end and p.ends_at>old.requested_start) then raise exception 'الموعد يتعارض مع حجز أو ورشة معتمدة' using errcode='23P01';end if;
 end if;
 if new_status='completed' and old.kind<>'need' and old.requested_end>now() then raise exception 'لا يمكن تسجيل التنفيذ قبل انتهاء الموعد';end if;
 update public.support_requests set status=new_status,review_note=case when mgr then coalesce(note,'') else review_note end,reviewed_by=case when mgr then uid else reviewed_by end,reviewed_at=case when mgr then now() else reviewed_at end,version=version+1,updated_at=now() where id=old.id;
 if old.kind='proposal' and new_status='approved' then
  insert into public.support_programs(source_request_id,title,presenter,audience,objectives,location,starts_at,ends_at) values(old.id,old.title,old.presenter,old.audience,old.details,old.location,old.requested_start,old.requested_end) returning id into pid;
 elsif old.kind='proposal' then
  update public.support_programs set status=case when new_status='completed' then 'completed' else 'cancelled' end where source_request_id=old.id returning id into pid;
 end if;
 return jsonb_build_object('id',old.id,'version',old.version+1,'status',new_status,'program_id',pid);
end $$;
create function support_private.save_impact(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); req uuid:=(payload->>'request_id')::uuid; p jsonb:=payload-'request_id'; old public.support_impacts; pid uuid:=nullif(payload->>'program_id','')::uuid; did bigint:=nullif(payload->>'documentation_id','')::bigint; rid uuid;
begin
 if not support_private.member() then raise exception 'يلزم حساب مدرسة معتمد' using errcode='42501';end if;
 if req is null or p-array['program_id','documentation_id','applied_on','application','evidence','followup','before_level','after_level']<>'{}'::jsonb then raise exception 'بيانات قياس الأثر غير صالحة';end if;
 if num_nonnulls(pid,did)<>1 then raise exception 'اختاري برنامجًا أو تقرير ورشة واحدًا';end if;
 if pid is not null and not exists(select 1 from public.support_programs where id=pid and status in ('planned','completed')) then raise exception 'البرنامج غير متاح' using errcode='42501';end if;
 if did is not null and not exists(select 1 from public.documentations d where d.id=did and coalesce(d.activity_type,nullif(d.details->>'type',''))='ورشة تدريبية' and (d.created_by=uid or support_private.reports_reader())) then raise exception 'تقرير الورشة غير متاح لحسابكِ' using errcode='42501';end if;
 if (payload->>'applied_on')::date>(now() at time zone 'Asia/Bahrain')::date then raise exception 'تاريخ التطبيق لا يكون في المستقبل';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));
 select * into old from public.support_impacts where created_by=uid and request_id=req;
 if old.id is not null then
  if old.submission<>p then raise exception 'هذه المحاولة محفوظة ببيانات مختلفة';end if;
  return jsonb_build_object('id',old.id,'recovered',true);
 end if;
 insert into public.support_impacts(created_by,creator_name,request_id,program_id,documentation_id,applied_on,application,evidence,followup,before_level,after_level,submission)
 values(uid,(select full_name from public.profiles where id=uid),req,pid,did,(payload->>'applied_on')::date,payload->>'application',coalesce(payload->>'evidence',''),coalesce(payload->>'followup',''),nullif(payload->>'before_level','')::smallint,nullif(payload->>'after_level','')::smallint,p) returning id into rid;
 return jsonb_build_object('id',rid,'recovered',false);
end $$;
create function public.support_center_context() returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول بحساب المدرسة' using errcode='42501';end if;
 return jsonb_build_object('manager',support_private.manager(),'reports_reader',support_private.reports_reader(),'profile',(select jsonb_build_object('id',id,'full_name',full_name,'department',department) from public.profiles where id=auth.uid()));
end $$;
create function public.save_support_request(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select support_private.save_request(payload)$$;
create function public.review_support_request(request_uuid uuid,new_status text,note text,expected_version integer) returns jsonb language sql security invoker set search_path='' as $$select support_private.review_request(request_uuid,new_status,note,expected_version)$$;
create function public.save_support_impact(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select support_private.save_impact(payload)$$;
create function public.support_center_summary() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare counts jsonb;
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول' using errcode='42501';end if;
 with workshops as (select coalesce(support_program_id::text,'doc:'||id::text) workshop,max(training_beneficiaries) participants from public.documentations where coalesce(activity_type,nullif(details->>'type',''))='ورشة تدريبية' group by 1)
 select jsonb_build_object('needs',(select count(*) from public.support_requests where kind='need' and status<>'cancelled'),'workshops',count(*),'beneficiaries',sum(participants),'known_participants_workshops',count(participants),'unknown_participants_workshops',count(*)-count(participants),'impacts',(select count(*) from public.support_impacts),'pending',(select count(*) from public.support_requests where status='pending'),'scope',case when support_private.manager() then 'center' else 'own' end) into counts from workshops;
 return counts;
end $$;
-- Only busy times are disclosed to other members, never the requester or purpose.
create function support_private.busy_times(from_date date,to_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول' using errcode='42501';end if;
 if from_date is null or to_date is null or to_date<from_date or to_date-from_date>31 then raise exception 'اختاري فترة لا تتجاوز شهرًا';end if;
 return coalesce((select jsonb_agg(x order by x.starts_at) from (
 select requested_start starts_at,requested_end ends_at from public.support_requests where kind='booking' and status='approved' and requested_start<((to_date+1)::timestamp at time zone 'Asia/Bahrain') and requested_end>(from_date::timestamp at time zone 'Asia/Bahrain')
 union all select starts_at,ends_at from public.support_programs where status='planned' and starts_at<((to_date+1)::timestamp at time zone 'Asia/Bahrain') and ends_at>(from_date::timestamp at time zone 'Asia/Bahrain')) x),'[]'::jsonb);
end $$;
create function public.support_busy_times(from_date date,to_date date) returns jsonb language sql security invoker set search_path='' as $$select support_private.busy_times(from_date,to_date)$$;
revoke all on all functions in schema support_private from public,anon,authenticated;
grant execute on all functions in schema support_private to authenticated;
revoke all on function public.support_center_context(),public.save_support_request(jsonb),public.review_support_request(uuid,text,text,integer),public.save_support_impact(jsonb),public.support_center_summary(),public.support_busy_times(date,date) from public,anon;
grant execute on function public.support_center_context(),public.save_support_request(jsonb),public.review_support_request(uuid,text,text,integer),public.save_support_impact(jsonb),public.support_center_summary(),public.support_busy_times(date,date) to authenticated;
commit;
