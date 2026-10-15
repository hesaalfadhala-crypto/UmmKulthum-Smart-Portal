-- Additive migration: existing documents, grants and deletion workflow are retained.
alter table public.documentations add column execution_scope text check(execution_scope in('internal','external')),add column organizing_entity text,add column hosting_entity text;
create index documentation_scope_date on public.documentations(execution_scope,activity_date) where deleted_at is null;
insert into public.school_tags(kind,name) values('project','أنتِ تستحقين الشكر') on conflict do nothing;
create table documentation_private.recognition_access(user_id uuid primary key references public.profiles(id),can_write boolean not null default false,can_read boolean not null default false);
alter table documentation_private.recognition_access enable row level security;
revoke all on documentation_private.recognition_access from public,anon,authenticated;
create function documentation_private.recognition_allowed(writing boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (documentation_private.can_manage() or exists(select 1 from documentation_private.recognition_access a where a.user_id=auth.uid() and case when writing then a.can_write else a.can_read or a.can_write end))
$$;
create function documentation_private.is_recognition(d jsonb,p text) returns boolean language sql immutable set search_path='' as $$select coalesce(d->'projects' @> '["أنتِ تستحقين الشكر"]'::jsonb,false) or coalesce(p,'') like '%أنتِ تستحقين الشكر%' or coalesce(d ? 'recognition',false)$$;
create policy recognition_visibility_guard on public.documentations as restrictive for select to authenticated using(not documentation_private.is_recognition(details,projects) or (select documentation_private.recognition_allowed(false)));
create policy recognition_insert_guard on public.documentations as restrictive for insert to authenticated with check(not documentation_private.is_recognition(details,projects) or (select documentation_private.recognition_allowed(true)));
create policy recognition_delegates_read on public.documentations for select to authenticated using(deleted_at is null and documentation_private.is_recognition(details,projects) and (select documentation_private.recognition_allowed(false)));
create function public.recognition_context() returns jsonb language sql stable security invoker set search_path='' as $$select jsonb_build_object('can_write',documentation_private.recognition_allowed(true),'can_read',documentation_private.recognition_allowed(false))$$;
create function documentation_private.recognition_staff() returns table(id uuid,full_name text,department text) language plpgsql stable security definer set search_path='' as $$
begin
 if not documentation_private.recognition_allowed(true) then raise exception 'ليست لديكِ صلاحية إدخال التكريم.' using errcode='42501';end if;
 return query select p.id,p.full_name,coalesce(nullif(btrim(p.department),''),'الإدارة المدرسية') from public.profiles p where nullif(btrim(p.full_name),'') is not null order by p.full_name;
end$$;
create function public.recognition_staff() returns table(id uuid,full_name text,department text) language sql stable security invoker set search_path='' as $$select * from documentation_private.recognition_staff()$$;
create function documentation_private.validate_execution_recognition() returns trigger language plpgsql security definer set search_path='' as $$
declare d jsonb:=coalesce(new.details,'{}');r jsonb;ids jsonb;recipients jsonb;awards jsonb;hours numeric;kind text;typ text:=coalesce(new.activity_type,d->>'type');
begin
 if typ in('فعالية','ورشة تدريبية','مبادرة','ملتقى') then
  new.execution_scope:=coalesce(new.execution_scope,nullif(d->>'executionScope',''),case when typ='ورشة تدريبية' then new.workshop_type end);
  if new.execution_scope is null or new.execution_scope not in('internal','external') then raise exception 'نطاق التنفيذ مطلوب: داخلية أو خارجية.';end if;
  new.organizing_entity:=nullif(btrim(coalesce(new.organizing_entity,d->>'organizingEntity')),'');new.hosting_entity:=nullif(btrim(coalesce(new.hosting_entity,d->>'hostingEntity')),'');
  if new.execution_scope='external' and (coalesce(length(new.organizing_entity),0) not between 1 and 300 or coalesce(length(new.hosting_entity),0) not between 1 and 300) then raise exception 'الجهة المنظمة والجهة المستضيفة مطلوبتان للنشاط الخارجي.';end if;
  if new.execution_scope='internal' then new.organizing_entity:=null;new.hosting_entity:=null;end if;
  d:=d||jsonb_build_object('executionScope',new.execution_scope,'organizingEntity',new.organizing_entity,'hostingEntity',new.hosting_entity);
  if typ='ورشة تدريبية' then
   new.workshop_type:=new.execution_scope;new.executing_agency:=new.organizing_entity;
   d:=d||jsonb_build_object('workshopType',new.execution_scope,'executingAgency',new.organizing_entity);
  end if;
 else new.execution_scope:=null;new.organizing_entity:=null;new.hosting_entity:=null;d:=d-array['executionScope','organizingEntity','hostingEntity'];end if;
 if documentation_private.is_recognition(d,new.projects) then
  if not documentation_private.recognition_allowed(true) then raise exception 'إضافة التكريم متاحة للمخولات فقط.' using errcode='42501';end if;
  if not coalesce(d->'projects' @> '["أنتِ تستحقين الشكر"]'::jsonb,false) then raise exception 'اختاري مشروع أنتِ تستحقين الشكر.';end if;
  r:=d->'recognition';
  if jsonb_typeof(r) is distinct from 'object' then raise exception 'بيانات التكريم مطلوبة.';end if;
  if coalesce(length(btrim(r->>'title')),0) not between 1 and 300 or coalesce(length(btrim(r->>'reason')),0) not between 1 and 6000 or coalesce(length(btrim(r->>'presenter')),0) not between 1 and 300 then raise exception 'عنوان التكريم وسببه والجهة المقدمة مطلوبة.';end if;
  if coalesce(r->>'date','') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'تاريخ التكريم مطلوب.';end if;
  new.activity:=btrim(r->>'title');new.activity_date:=(r->>'date')::date;
  ids:=r->'recipientIds';
  if jsonb_typeof(ids) is distinct from 'array' or jsonb_array_length(ids) not between 1 and 150 then raise exception 'اختاري مكرمة واحدة على الأقل.';end if;
  if (select count(distinct value) from jsonb_array_elements_text(ids))<>jsonb_array_length(ids) then raise exception 'لا يجوز تكرار المكرمة في الفعالية نفسها.';end if;
  select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'department',coalesce(nullif(btrim(p.department),''),'الإدارة المدرسية')) order by p.full_name) into recipients from public.profiles p where p.id in(select value::uuid from jsonb_array_elements_text(ids));
  if coalesce(jsonb_array_length(recipients),0)<>jsonb_array_length(ids) then raise exception 'إحدى المكرمات غير موجودة في حسابات المدرسة.';end if;
  kind:=r->>'kind';
  if kind is null or kind not in('مبادرة متميزة','تميز في الأداء الوظيفي','جهود استثنائية','تفعيل الأنشطة والفعاليات','تعاون ومساندة الزميلات','تحقيق إنجاز أو مركز متقدم','أخرى') then raise exception 'نوع التكريم غير صالح.';end if;
  if kind='أخرى' and coalesce(length(btrim(r->>'kindOther')),0) not between 1 and 500 then raise exception 'وضحي نوع التكريم الآخر.';end if;
  awards:=r->'awards';
  if jsonb_typeof(awards) is distinct from 'array' or jsonb_array_length(awards) not between 1 and 7 or exists(select 1 from jsonb_array_elements_text(awards) a where a not in('شهادة شكر وتقدير','بطاقة شكر إلكترونية','ساعات سعادة','تكريم في الطابور الصباحي','تكريم في اجتماع أو فعالية','هدية رمزية','أخرى')) then raise exception 'اختاري نوع التقدير المقدم.';end if;
  if awards @> '["أخرى"]' and coalesce(length(btrim(r->>'awardOther')),0) not between 1 and 500 then raise exception 'وضحي نوع التقدير الآخر.';end if;
  if awards @> '["ساعات سعادة"]' then
   hours:=(r->>'hours')::numeric;
   if hours is null or hours<=0 or hours>1000 or hours<>round(hours,2) then raise exception 'أدخلي ساعات السعادة لكل مكرمة أكبر من صفر وحتى 1000 بمنزلتين عشريتين.';end if;
  else hours:=0;end if;
  r:=jsonb_build_object('title',new.activity,'date',new.activity_date,'recipientIds',ids,'recipients',recipients,'kind',kind,'kindOther',case when kind='أخرى' then btrim(r->>'kindOther') else null end,'reason',btrim(r->>'reason'),'awards',awards,'awardOther',case when awards @> '["أخرى"]' then btrim(r->>'awardOther') else null end,'hours',hours,'presenter',btrim(r->>'presenter'),'notes',left(coalesce(r->>'notes',''),6000));
  d:=d||jsonb_build_object('recognition',r,'activity',new.activity,'date',new.activity_date);
 end if;
 new.details:=d;return new;
end$$;
-- Insert-only validation does not revalidate old records during soft delete/restore.
create trigger documentation_execution_fields before insert on public.documentations for each row execute function documentation_private.validate_execution_recognition();
revoke all on function documentation_private.recognition_allowed(boolean),documentation_private.is_recognition(jsonb,text),documentation_private.recognition_staff(),documentation_private.validate_execution_recognition() from public,anon,authenticated;
grant execute on function documentation_private.recognition_allowed(boolean),documentation_private.is_recognition(jsonb,text),documentation_private.recognition_staff() to authenticated;
revoke all on function public.recognition_context(),public.recognition_staff() from public,anon;
grant execute on function public.recognition_context(),public.recognition_staff() to authenticated;

-- Proposals and approved programs share the same scope semantics; executing_agency is the existing organizer column.
alter table public.support_requests add column hosting_entity text;
alter table public.support_programs add column hosting_entity text;
create or replace function support_private.save_request(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); req uuid:=(payload->>'request_id')::uuid; p jsonb:=payload-'request_id'; old public.support_requests; start_at timestamptz; end_at timestamptz; rid uuid;
begin
 if not support_private.member() then raise exception 'يلزم تسجيل الدخول بحساب المدرسة' using errcode='42501';end if;
 if req is null or jsonb_typeof(payload)<>'object' or p-array['kind','title','department','audience','priority','details','presenter','location','date','from','to','workshop_type','executing_agency','hosting_entity']<>'{}'::jsonb then raise exception 'بيانات الطلب غير صالحة';end if;
 if payload->>'kind' is null or payload->>'kind' not in ('need','proposal','booking') then raise exception 'نوع الطلب غير صالح';end if;
 if payload->>'kind'='proposal' and (coalesce(payload->>'workshop_type','') not in('internal','external') or payload->>'workshop_type'='external' and length(btrim(coalesce(payload->>'executing_agency',''))) not between 1 and 300) then raise exception 'نطاق التنفيذ والجهة المنظمة الخارجية مطلوبان.';end if;
 if payload->>'kind'='proposal' and payload->>'workshop_type'='external' and length(btrim(coalesce(payload->>'hosting_entity',''))) not between 1 and 300 then raise exception 'الجهة المستضيفة مطلوبة للورشة الخارجية.';end if;
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
 insert into public.support_requests(created_by,creator_name,request_id,kind,title,department,audience,priority,details,presenter,location,requested_start,requested_end,submission,workshop_type,executing_agency,hosting_entity)
 values(uid,(select full_name from public.profiles where id=uid),req,payload->>'kind',payload->>'title',coalesce(payload->>'department',''),coalesce(payload->>'audience','teachers'),coalesce(payload->>'priority','normal'),coalesce(payload->>'details',''),coalesce(nullif(payload->>'presenter',''),(select full_name from public.profiles where id=uid)),coalesce(nullif(payload->>'location',''),'مركز الدعم'),start_at,end_at,p,case when payload->>'kind'='proposal' then payload->>'workshop_type' end,case when payload->>'kind'='proposal' and payload->>'workshop_type'='external' then btrim(payload->>'executing_agency') end,case when payload->>'kind'='proposal' and payload->>'workshop_type'='external' then btrim(payload->>'hosting_entity') end) returning id into rid;
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
  insert into public.support_programs(source_request_id,title,presenter,audience,objectives,location,starts_at,ends_at,workshop_type,executing_agency,hosting_entity) values(old.id,old.title,old.presenter,old.audience,old.details,old.location,old.requested_start,old.requested_end,old.workshop_type,old.executing_agency,old.hosting_entity) returning id into pid;
 elsif old.kind='proposal' then
  update public.support_programs set status=case when new_status='completed' then 'completed' else 'cancelled' end where source_request_id=old.id returning id into pid;
 end if;
 return jsonb_build_object('id',old.id,'version',old.version+1,'status',new_status,'program_id',pid);
end $$;

