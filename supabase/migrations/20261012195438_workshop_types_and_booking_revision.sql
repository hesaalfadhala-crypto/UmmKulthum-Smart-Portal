alter table public.documentations add column workshop_type text check(workshop_type in('internal','external')),add column executing_agency text;
alter table public.support_requests add column workshop_type text check(workshop_type in('internal','external')),add column executing_agency text;
alter table public.support_programs add column workshop_type text check(workshop_type in('internal','external')),add column executing_agency text;
alter table public.support_requests drop constraint support_requests_status_check;
alter table public.support_requests add constraint support_requests_status_check check(status in('pending','approved','declined','cancelled','completed','needs_revision'));
create or replace function support_private.validate_documentation() returns trigger language plpgsql set search_path='' as $$
begin
 if coalesce(new.activity_type,nullif(new.details->>'type',''))='ورشة تدريبية' then
  if not support_private.member() then raise exception 'يلزم حساب مدرسة معتمد' using errcode='42501';end if;
  new.workshop_type:=coalesce(new.workshop_type,nullif(new.details->>'workshopType',''));
  new.executing_agency:=coalesce(new.executing_agency,nullif(new.details->>'executingAgency',''));
  if new.workshop_type is null or new.workshop_type not in('internal','external') then raise exception 'اختاري نوع الورشة: داخلية أو خارجية.';end if;
  if new.workshop_type='external' and length(btrim(coalesce(new.executing_agency,''))) not between 1 and 300 then raise exception 'الجهة المنفذة مطلوبة للورشة الخارجية.';end if;
  if new.workshop_type='internal' then new.executing_agency:=null;new.details:=jsonb_set(new.details,'{executingAgency}','""');end if;

  if nullif(new.details->>'centerProgramId','') is not null then
   if new.support_program_id is not null and new.support_program_id<> (new.details->>'centerProgramId')::uuid then raise exception 'البرنامج المرتبط غير متطابق';end if;
   new.support_program_id:=(new.details->>'centerProgramId')::uuid;
  end if;
  if nullif(new.details->>'trainingBeneficiaries','') is not null then
   if new.training_beneficiaries is not null and new.training_beneficiaries<>(new.details->>'trainingBeneficiaries')::integer then raise exception 'عدد المستفيدات غير متطابق';end if;
   new.training_beneficiaries:=(new.details->>'trainingBeneficiaries')::integer;
  end if;
  if new.support_program_id is not null and exists(select 1 from public.support_programs p where p.id=new.support_program_id and p.workshop_type is not null and p.workshop_type<>new.workshop_type) then raise exception 'نوع الورشة لا يطابق البرنامج المعتمد.';end if;
  if new.support_program_id is not null and not exists(select 1 from public.support_programs p where p.id=new.support_program_id and p.status in ('planned','completed')) then raise exception 'البرنامج غير متاح للتوثيق';end if;
 else
  if new.support_program_id is not null or new.training_beneficiaries is not null then raise exception 'ربط المركز متاح لتوثيق الورش فقط';end if;
 end if;
 return new;
end $$;
drop trigger support_documentation_fields on public.documentations;
create trigger support_documentation_fields before insert or update of activity_type,details,support_program_id,training_beneficiaries,workshop_type,executing_agency on public.documentations for each row execute function support_private.validate_documentation();
create or replace function support_private.save_request(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); req uuid:=(payload->>'request_id')::uuid; p jsonb:=payload-'request_id'; old public.support_requests; start_at timestamptz; end_at timestamptz; rid uuid;
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول بحساب المدرسة' using errcode='42501';end if;
 if req is null or jsonb_typeof(payload)<>'object' or p-array['kind','title','department','audience','priority','details','presenter','location','date','from','to','workshop_type','executing_agency']<>'{}'::jsonb then raise exception 'بيانات الطلب غير صالحة';end if;
 if payload->>'kind' is null or payload->>'kind' not in ('need','proposal','booking') then raise exception 'نوع الطلب غير صالح';end if;
 if payload->>'kind'='proposal' and (coalesce(payload->>'workshop_type','') not in('internal','external') or payload->>'workshop_type'='external' and length(btrim(coalesce(payload->>'executing_agency',''))) not between 1 and 300) then raise exception 'نوع الورشة والجهة المنفذة الخارجية مطلوبان.';end if;
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
 insert into public.support_requests(created_by,creator_name,request_id,kind,title,department,audience,priority,details,presenter,location,requested_start,requested_end,submission,workshop_type,executing_agency)
 values(uid,(select full_name from public.profiles where id=uid),req,payload->>'kind',payload->>'title',coalesce(payload->>'department',''),coalesce(payload->>'audience','teachers'),coalesce(payload->>'priority','normal'),coalesce(payload->>'details',''),coalesce(nullif(payload->>'presenter',''),(select full_name from public.profiles where id=uid)),coalesce(nullif(payload->>'location',''),'مركز الدعم'),start_at,end_at,p,case when payload->>'kind'='proposal' then payload->>'workshop_type' end,case when payload->>'kind'='proposal' and payload->>'workshop_type'='external' then btrim(payload->>'executing_agency') end) returning id into rid;
 return jsonb_build_object('id',rid,'status','pending','recovered',false);
end $$;
create or replace function support_private.review_request(request_uuid uuid,new_status text,note text,expected_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); old public.support_requests; mgr boolean:=support_private.manager(); pid uuid;
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول' using errcode='42501';end if;
 -- Serialize approvals across bookings and workshop proposals for the same center.
 perform pg_advisory_xact_lock(hashtextextended('ummkulthum-support-center-calendar',0));
 select * into old from public.support_requests where id=request_uuid for update;
 if old.id is null or (not mgr and old.created_by<>uid) then raise exception 'الطلب غير متاح لحسابكِ' using errcode='42501';end if;
 if expected_version is null or expected_version<>old.version then raise exception 'تم تحديث الطلب. حدّثي القائمة قبل المراجعة' using errcode='40001';end if;
 if not mgr and (new_status<>'cancelled' or old.status not in ('pending','approved') or old.requested_start<=now()) then raise exception 'لا تملكين صلاحية لهذا الإجراء' using errcode='42501';end if;
 if new_status is null or new_status not in ('approved','declined','cancelled','completed','needs_revision') or length(coalesce(note,''))>4000 then raise exception 'حالة المراجعة غير صالحة';end if;
 if new_status='needs_revision' and (not mgr or old.kind<>'booking' or length(btrim(coalesce(note,'')))<5) then raise exception 'طلب تعديل الموعد يحتاج ملاحظة من مسؤولة المركز.';end if;
 if old.status in ('declined','cancelled','completed') or old.status='approved' and new_status not in ('cancelled','completed','needs_revision') or old.status='pending' and new_status='completed' then raise exception 'هذا الانتقال غير متاح لحالة الطلب';end if;
 if new_status='approved' and old.kind<>'need' then
  if old.requested_start<now() then raise exception 'الموعد مضى. اطلبي موعدًا جديدًا';end if;
  if exists(select 1 from public.support_requests b where b.id<>old.id and lower(btrim(b.location))=lower(btrim(old.location)) and b.kind='booking' and b.status='approved' and b.requested_start<old.requested_end and b.requested_end>old.requested_start)
   or exists(select 1 from public.support_programs p where p.source_request_id<>old.id and lower(btrim(p.location))=lower(btrim(old.location)) and p.status='planned' and p.starts_at<old.requested_end and p.ends_at>old.requested_start) then raise exception 'الموعد يتعارض مع حجز أو ورشة معتمدة' using errcode='23P01';end if;
 end if;
 if new_status='completed' and old.kind<>'need' and old.requested_end>now() then raise exception 'لا يمكن تسجيل التنفيذ قبل انتهاء الموعد';end if;
 update public.support_requests set status=new_status,review_note=case when mgr then coalesce(note,'') else review_note end,reviewed_by=case when mgr then uid else reviewed_by end,reviewed_at=case when mgr then now() else reviewed_at end,version=version+1,updated_at=now() where id=old.id;
 if old.kind='proposal' and new_status='approved' then
  insert into public.support_programs(source_request_id,title,presenter,audience,objectives,location,starts_at,ends_at,workshop_type,executing_agency) values(old.id,old.title,old.presenter,old.audience,old.details,old.location,old.requested_start,old.requested_end,old.workshop_type,old.executing_agency) returning id into pid;
 elsif old.kind='proposal' then
  update public.support_programs set status=case when new_status='completed' then 'completed' else 'cancelled' end where source_request_id=old.id returning id into pid;
 end if;
 return jsonb_build_object('id',old.id,'version',old.version+1,'status',new_status,'program_id',pid);
end $$;

create function support_private.resubmit_booking(request_uuid uuid,starts_at timestamptz,ends_at timestamptz,location text,expected_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.support_requests;
begin
 if not support_private.member() then raise exception 'يلزم حساب المدرسة.' using errcode='42501';end if;
 select * into r from public.support_requests where id=request_uuid for update;
 if not found or r.created_by<>auth.uid() or r.kind<>'booking' or r.status<>'needs_revision' then raise exception 'طلب التعديل غير متاح.' using errcode='42501';end if;
 if r.version<>expected_version then raise exception 'حدّثي الطلب أولًا.' using errcode='40001';end if;
 if starts_at<now() or ends_at<=starts_at or length(btrim(location)) not between 1 and 300 then raise exception 'راجعي المكان والموعد الجديد.';end if;
 update public.support_requests set requested_start=starts_at,requested_end=ends_at,location=btrim(resubmit_booking.location),status='pending',version=version+1,updated_at=now() where id=request_uuid;
 return jsonb_build_object('id',request_uuid,'status','pending','version',r.version+1);
end $$;
create function public.resubmit_support_booking(request_uuid uuid,starts_at timestamptz,ends_at timestamptz,location text,expected_version integer) returns jsonb language sql security invoker set search_path='' as $$select support_private.resubmit_booking(request_uuid,starts_at,ends_at,location,expected_version)$$;
revoke all on function support_private.resubmit_booking(uuid,timestamptz,timestamptz,text,integer) from public,anon;
grant execute on function support_private.resubmit_booking(uuid,timestamptz,timestamptz,text,integer) to authenticated;
revoke all on function public.resubmit_support_booking(uuid,timestamptz,timestamptz,text,integer) from public,anon;
grant execute on function public.resubmit_support_booking(uuid,timestamptz,timestamptz,text,integer) to authenticated;
create function public.support_center_summary_filtered(department_filter text default '',from_date date default null,to_date date default null,year_filter text default '') returns jsonb language sql stable security invoker set search_path='' as $$
 with reports as(select * from public.documentations d where d.deleted_at is null and coalesce(d.activity_type,d.details->>'type')='ورشة تدريبية' and(department_filter='' or d.department=department_filter) and(from_date is null or d.activity_date>=from_date) and(to_date is null or d.activity_date<=to_date) and(year_filter='' or coalesce(d.academic_year,case when extract(month from d.activity_date)>=9 then extract(year from d.activity_date)::int::text||'-'||(extract(year from d.activity_date)::int+1)::text else (extract(year from d.activity_date)::int-1)::text||'-'||extract(year from d.activity_date)::int::text end)=year_filter)),
 workshops as(select coalesce(support_program_id::text,'doc:'||id::text) workshop,max(training_beneficiaries) participants,max(workshop_type) workshop_type from reports group by 1),
 needs as(select * from public.support_requests r where kind='need' and status<>'cancelled' and(department_filter='' or r.department=department_filter) and(from_date is null or r.created_at::date>=from_date) and(to_date is null or r.created_at::date<=to_date) and(year_filter='' or case when extract(month from r.created_at)>=9 then extract(year from r.created_at)::int::text||'-'||(extract(year from r.created_at)::int+1)::text else (extract(year from r.created_at)::int-1)::text||'-'||extract(year from r.created_at)::int::text end=year_filter)),
 impacts as(select i.* from public.support_impacts i where (i.program_id is not null and exists(select 1 from public.support_programs p where p.id=i.program_id and p.status<>'cancelled') or exists(select 1 from public.documentations active where active.deleted_at is null and active.id=i.documentation_id)) and(from_date is null or i.applied_on>=from_date) and(to_date is null or i.applied_on<=to_date) and(year_filter='' or case when extract(month from i.applied_on)>=9 then extract(year from i.applied_on)::int::text||'-'||(extract(year from i.applied_on)::int+1)::text else (extract(year from i.applied_on)::int-1)::text||'-'||extract(year from i.applied_on)::int::text end=year_filter) and(department_filter='' or exists(select 1 from reports r where r.id=i.documentation_id or r.support_program_id=i.program_id)))
 select jsonb_build_object('needs',(select count(*) from needs),'workshops',count(*),'beneficiaries',sum(participants),'known_participants_workshops',count(participants),'unknown_participants_workshops',count(*)-count(participants),'internal',count(*) filter(where workshop_type='internal'),'external',count(*) filter(where workshop_type='external'),'unknown_type',count(*) filter(where workshop_type is null),'impacts',(select count(*) from impacts),'pending',(select count(*) from public.support_requests where status='pending'),'scope',case when support_private.manager() then 'center' else 'own' end) from workshops
$$;
revoke all on function public.support_center_summary_filtered(text,date,date,text) from public,anon;
grant execute on function public.support_center_summary_filtered(text,date,date,text) to authenticated;
do $$begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='support_requests') then execute 'alter publication supabase_realtime add table public.support_requests';end if;
end$$;
