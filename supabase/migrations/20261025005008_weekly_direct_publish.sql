-- Publish staff plans directly. Retain draft, ownership, department and file policies.
-- Internal legacy 'approved' rows remain valid; new staff rows use 'published'.
alter table public.weekly_notifications add column content_key text;
create index weekly_notice_content on public.weekly_notifications(recipient_id,plan_id,event,content_key);
create function weekly_private.dedupe_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select md5(jsonb_build_object('body',p.body,'file',p.file_id)::text) into new.content_key from public.weekly_plans p where p.id=new.plan_id;
 perform pg_advisory_xact_lock(hashtextextended(new.recipient_id::text||new.plan_id::text||new.event,7));
 if exists(select 1 from public.weekly_notifications n where n.recipient_id=new.recipient_id and n.plan_id=new.plan_id and n.event=new.event and n.content_key=new.content_key) then return null;end if;
 return new;
end $$;
revoke all on function weekly_private.dedupe_notification() from public,anon,authenticated;
create trigger weekly_notice_once before insert on public.weekly_notifications for each row execute function weekly_private.dedupe_notification();

CREATE OR REPLACE FUNCTION weekly_private.save_plan(payload jsonb, expected_version integer, operation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 desired:=case when k='staff' and coalesce((payload->>'submit')::boolean,false) then 'published' when k='staff' and p.status in('approved','published') then 'published' else 'draft' end;
 if desired='published' and fid is null and not exists(select 1 from jsonb_array_elements(b->'slots') x where length(trim(x->>'text'))>0) then raise exception 'أدخلي المهام أو ارفعي ملف الخطة قبل نشرها.'; end if;
 if expected_version>0 and p.body=b and p.file_id is not distinct from fid and p.status=desired then
 result:=jsonb_build_object('id',pid,'version',p.version,'status',p.status);
 insert into weekly_private.operations values(operation_id,uid,arg,result);return result;end if;
 update public.weekly_plans set body=b,file_id=fid,status=desired,version=case when expected_version=0 then 1 else version+1 end,updated_at=now(),submitted_at=case when desired='published' then coalesce(submitted_at,now()) else submitted_at end,reviewed_by=null,reviewer_name=null,reviewed_at=null,review_note=null,published_at=case when desired='published' then coalesce(published_at,now()) else published_at end where id=pid returning * into p;
 if desired='published' then
  insert into public.weekly_notifications(recipient_id,plan_id,event,message)
  select x.id,pid,'staff_published','نشر أو تحديث خطة أسبوعية: '||p.owner_name||' — الأسبوع '||w.week_number from public.profiles x where
  (x.role in('principal','assistant_principal') and x.school_access='all') or (x.role in('assistant_principal','first_teacher','coordinator') and x.id<>uid and exists(select 1 from public.observation_access a where a.user_id=x.id and a.department=p.department and a.can_edit));
 end if;
 result:=jsonb_build_object('id',pid,'version',p.version,'status',p.status);
 insert into weekly_private.operations values(operation_id,uid,arg,result); return result;
end $function$;

create or replace function weekly_private.shared_plan(plan_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(
 select 1 from public.weekly_plans p join public.weekly_staff s on s.id=p.staff_id
 join public.profiles owner on owner.id=s.user_id join public.profiles viewer on viewer.id=auth.uid()
 where p.id=plan_uuid and p.kind='staff' and p.status in('approved','published') and s.active and
 (owner.role='assistant_principal' or owner.role in('first_teacher','coordinator') and nullif(btrim(p.department),'') is not null and (
 p.department=any(case when cardinality(viewer.departments)>0 then viewer.departments else array[viewer.department] end)
 or (p.department=any(owner.departments) and owner.departments && case when cardinality(viewer.departments)>0 then viewer.departments else array[viewer.department] end)
 )))
$$;

-- Preserve a rollback snapshot before releasing the three previously submitted plans.
create table weekly_private.direct_publish_backup as select * from public.weekly_plans where kind='staff' and status='submitted';
alter table weekly_private.direct_publish_backup enable row level security;
revoke all on weekly_private.direct_publish_backup from public,anon,authenticated;
update public.weekly_plans set status='published',published_at=coalesce(published_at,now()),version=version+1,updated_at=now() where kind='staff' and status='submitted';
