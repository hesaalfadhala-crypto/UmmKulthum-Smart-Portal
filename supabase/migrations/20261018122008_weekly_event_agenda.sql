-- New service only: no existing profile, report or storage policy is replaced.
create schema agenda_private;
revoke all on schema agenda_private from public,anon;grant usage on schema agenda_private to authenticated;
create table agenda_private.approvers(user_id uuid primary key references profiles(id));
alter table agenda_private.approvers enable row level security;revoke all on agenda_private.approvers from public,anon,authenticated;
insert into agenda_private.approvers select id from profiles where (role in('principal','assistant_principal') and school_access='all') or (role='assistant_principal' and full_name in('AISHAH MOHAMMAD YAQOOB ABDULMAJEED','HIBA ALI HUSSAIN SALMAN'));
do $$begin if (select count(*) from agenda_private.approvers)<>4 then raise exception 'Verify the four agenda approvers before deployment';end if;end$$;
create function agenda_private.member() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid())$$;
create function agenda_private.manager() returns boolean language sql stable security definer set search_path='' as $$select agenda_private.member() and exists(select 1 from agenda_private.approvers where user_id=auth.uid())$$;
create table public.agenda_events(
 id uuid primary key default gen_random_uuid(),created_by uuid not null references profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 request_id uuid not null,series_id uuid not null,title text not null,kind text not null check(kind in('school_head','supervision','parents','event','workshop','honor','other')),kind_other text not null default '',event_date date not null check(extract(dow from event_date) between 0 and 4),
 slot text not null check(slot in('assembly','break','both','other')),starts_at time,ends_at time,department text not null,responsible_ids uuid[] not null,responsible_names text[] not null,location text not null,audience text not null,description text not null,notes text not null default '',student_visible boolean not null default false,
 status text not null default 'pending' check(status in('pending','approved','needs_changes')),review_note text not null default '',reviewed_by uuid references profiles(id),reviewed_at timestamptz,version integer not null default 1,report_id bigint references documentations(id),
 check(slot<>'other' or (starts_at is not null and ends_at>starts_at)),check(kind<>'other' or length(btrim(kind_other)) between 1 and 300),check(kind not in('school_head','supervision','parents') or student_visible=false)
);
create index agenda_date_status on agenda_events(event_date,status);create index agenda_owner_date on agenda_events(created_by,event_date);
alter table agenda_events enable row level security;revoke all on agenda_events from public,anon,authenticated;grant select on agenda_events to authenticated;
create policy agenda_visible on agenda_events for select to authenticated using((select agenda_private.member()) and (status='approved' or created_by=(select auth.uid()) or (select agenda_private.manager())));
create table agenda_private.operations(user_id uuid not null,request_id uuid not null,payload jsonb not null,result jsonb not null,primary key(user_id,request_id));
create table agenda_private.history(id bigint generated always as identity primary key,event_id uuid not null,actor uuid not null,action text not null,reason text,previous jsonb,created_at timestamptz not null default now());
alter table agenda_private.operations enable row level security;alter table agenda_private.history enable row level security;revoke all on agenda_private.operations,agenda_private.history from public,anon,authenticated;
create function agenda_private.save_event(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();req uuid:=(payload->>'request_id')::uuid;old public.agenda_events;previous_op agenda_private.operations;rid uuid;series uuid:=gen_random_uuid();day date;last_day date;ids uuid[];names text[];result jsonb;list jsonb:='[]';changed_status text;
begin
 if not agenda_private.member() then raise exception 'يلزم حساب المدرسة' using errcode='42501';end if;
 if req is null or jsonb_typeof(payload)<>'object' or payload-array['request_id','id','version','title','kind','kind_other','event_date','slot','starts_at','ends_at','department','responsible_ids','location','audience','description','notes','student_visible','repeat_until']<>'{}' then raise exception 'بيانات الفعالية غير صالحة';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));select * into previous_op from agenda_private.operations where user_id=uid and request_id=req;
 if found then if previous_op.payload<>payload then raise exception 'محاولة محفوظة ببيانات مختلفة. افتحي السجل قبل التعديل';end if;return previous_op.result;end if;
 if coalesce(length(btrim(payload->>'title')),0) not between 1 and 300 or coalesce(length(btrim(payload->>'department')),0) not between 1 and 180 or coalesce(length(btrim(payload->>'location')),0) not between 1 and 300 or coalesce(length(btrim(payload->>'audience')),0) not between 1 and 500 or coalesce(length(btrim(payload->>'description')),0) not between 1 and 2000 or length(coalesce(payload->>'notes',''))>2000 then raise exception 'أكملي العنوان والقسم والمكان والفئة المستهدفة والوصف';end if;
 if coalesce(payload->>'kind','') not in('school_head','supervision','parents','event','workshop','honor','other') or coalesce(payload->>'slot','') not in('assembly','break','both','other') then raise exception 'اختاري النوع والفترة';end if;
 if jsonb_typeof(payload->'responsible_ids') is distinct from 'array' or jsonb_array_length(payload->'responsible_ids') not between 1 and 150 then raise exception 'اختاري المسؤولة أو المسؤولات';end if;
 select array_agg(distinct value::uuid) into ids from jsonb_array_elements_text(payload->'responsible_ids');
 if cardinality(ids)<>jsonb_array_length(payload->'responsible_ids') then raise exception 'أسماء المسؤولات مكررة';end if;
 select array_agg(full_name order by full_name) into names from public.profiles where id=any(ids);
 if cardinality(names) is distinct from cardinality(ids) then raise exception 'إحدى المسؤولات غير موجودة';end if;
 day:=(payload->>'event_date')::date;if day is null or extract(dow from day) not between 0 and 4 then raise exception 'اختاري تاريخًا من الأحد إلى الخميس';end if;
 if payload->>'id' is not null then
  select * into old from public.agenda_events where id=(payload->>'id')::uuid for update;
  if old.id is null or not (agenda_private.manager() or old.created_by=uid and old.status<>'approved') then raise exception 'لا تملكين تعديل هذه الفعالية أو أنها معتمدة' using errcode='42501';end if;
  if old.version<>(payload->>'version')::integer or payload->>'version' is null then raise exception 'تغيرت الفعالية. أعيدي تحميل أحدث نسخة';end if;
  if old.report_id is not null then raise exception 'الفعالية موثقة؛ لا يمكن تغيير بياناتها الأصلية';end if;
  if payload->>'repeat_until' is not null then raise exception 'التكرار يحدد عند الإنشاء فقط؛ تعديل السجل يؤثر في هذا اليوم وحده';end if;
  insert into agenda_private.history(event_id,actor,action,previous) values(old.id,uid,'edit',to_jsonb(old));
  update public.agenda_events set title=btrim(payload->>'title'),kind=payload->>'kind',kind_other=btrim(coalesce(payload->>'kind_other','')),event_date=day,slot=payload->>'slot',starts_at=case when payload->>'slot'='other' then (payload->>'starts_at')::time end,ends_at=case when payload->>'slot'='other' then (payload->>'ends_at')::time end,department=btrim(payload->>'department'),responsible_ids=ids,responsible_names=names,location=btrim(payload->>'location'),audience=btrim(payload->>'audience'),description=btrim(payload->>'description'),notes=coalesce(payload->>'notes',''),student_visible=coalesce((payload->>'student_visible')::boolean,false),status='pending',review_note='',reviewed_by=null,reviewed_at=null,version=version+1,updated_at=now() where id=old.id;
  list:=jsonb_build_array(old.id);
 else
  last_day:=coalesce((payload->>'repeat_until')::date,day);if last_day<day or last_day>day+364 then raise exception 'نهاية التكرار يجب أن تكون خلال سنة من البداية';end if;
  while day<=last_day loop
   insert into public.agenda_events(created_by,request_id,series_id,title,kind,kind_other,event_date,slot,starts_at,ends_at,department,responsible_ids,responsible_names,location,audience,description,notes,student_visible)
   values(uid,req,series,btrim(payload->>'title'),payload->>'kind',coalesce(payload->>'kind_other',''),day,payload->>'slot',case when payload->>'slot'='other' then (payload->>'starts_at')::time end,case when payload->>'slot'='other' then (payload->>'ends_at')::time end,btrim(payload->>'department'),ids,names,btrim(payload->>'location'),btrim(payload->>'audience'),btrim(payload->>'description'),coalesce(payload->>'notes',''),coalesce((payload->>'student_visible')::boolean,false)) returning id into rid;
   list:=list||jsonb_build_array(rid);day:=day+7;
  end loop;
 end if;
 result:=jsonb_build_object('ids',list);insert into agenda_private.operations values(uid,req,payload,result);return result;
end $$;
create function agenda_private.review_event(event_id uuid,decision text,note text,expected_version integer,request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.agenda_events;op agenda_private.operations;p jsonb:=jsonb_build_object('event_id',event_id,'decision',decision,'note',note,'version',expected_version);result jsonb;
begin
 if not agenda_private.manager() then raise exception 'الاعتماد متاح للمديرة والمديرات المساعدات المخولات فقط' using errcode='42501';end if;
 if request_id is null or expected_version is null then raise exception 'محاولة المراجعة غير صالحة';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||request_id::text,0));select * into op from agenda_private.operations o where o.user_id=auth.uid() and o.request_id=review_event.request_id;
 if found then if op.payload<>p then raise exception 'محاولة مراجعة محفوظة بقرار مختلف';end if;return op.result;end if;
 select * into old from public.agenda_events where id=event_id for update;
 if old.id is null or old.version<>expected_version then raise exception 'تغيرت الفعالية. حدّثي الصفحة';end if;
 if decision not in('approve','return','revoke') then raise exception 'قرار غير صالح';end if;
 if decision in('return','revoke') and coalesce(length(btrim(note)),0) not between 1 and 2000 then raise exception 'سبب الإرجاع أو إلغاء الاعتماد مطلوب';end if;
 if decision='revoke' and old.status<>'approved' then raise exception 'الفعالية غير معتمدة';end if;
 if decision in('return','approve') and old.status='approved' then raise exception 'الفعالية معتمدة بالفعل؛ استخدمي إلغاء الاعتماد مع السبب';end if;
 insert into agenda_private.history(event_id,actor,action,reason,previous) values(old.id,auth.uid(),decision,note,to_jsonb(old));
 update public.agenda_events set status=case when decision='approve' then 'approved' else 'needs_changes' end,review_note=coalesce(note,''),reviewed_by=auth.uid(),reviewed_at=now(),version=version+1,updated_at=now() where id=old.id;
 result:=jsonb_build_object('id',old.id,'version',old.version+1);insert into agenda_private.operations values(auth.uid(),request_id,p,result);return result;
end $$;
create function public.agenda_context() returns jsonb language sql stable security invoker set search_path='' as $$select jsonb_build_object('member',agenda_private.member(),'can_approve',agenda_private.manager())$$;
create function public.save_agenda_event(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select agenda_private.save_event(payload)$$;
create function public.review_agenda_event(event_id uuid,decision text,note text,expected_version integer,request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select agenda_private.review_event(event_id,decision,note,expected_version,request_id)$$;
create function agenda_private.staff() returns table(id uuid,full_name text,department text) language sql stable security definer set search_path='' as $$select id,full_name,department from public.profiles where agenda_private.member() order by full_name$$;
create function public.agenda_staff() returns table(id uuid,full_name text,department text) language sql stable security invoker set search_path='' as $$select * from agenda_private.staff()$$;
-- Link reports atomically at insert time. A competing save cannot create a second report.
alter table public.documentations add column agenda_event_id uuid references public.agenda_events(id);
create unique index documentation_one_per_agenda_event on documentations(agenda_event_id) where agenda_event_id is not null;
create function agenda_private.check_report() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.agenda_events;
begin
 if tg_op='UPDATE' then
  if new.agenda_event_id is distinct from old.agenda_event_id then raise exception 'رابط الفعالية الأصلي لا يتغير';end if;
  return new;
 end if;
 if new.agenda_event_id is null then return new;end if;
 select * into e from public.agenda_events where id=new.agenda_event_id for update;
 if not agenda_private.member() or e.id is null or not (e.created_by=auth.uid() or agenda_private.manager()) then raise exception 'لا تملكين توثيق هذه الفعالية' using errcode='42501';end if;
 if e.status<>'approved' or e.event_date>(now() at time zone 'Asia/Bahrain')::date then raise exception 'التوثيق للفعاليات المعتمدة التي حل تاريخ تنفيذها فقط';end if;
 if e.report_id is not null then raise exception 'الفعالية موثقة بالفعل؛ افتحي تقريرها الأصلي';end if;
 return new;
end $$;
create function agenda_private.link_report() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.agenda_event_id is not null then
  update public.agenda_events set report_id=new.id,updated_at=now(),version=version+1 where id=new.agenda_event_id;
 end if;return new;
end $$;
create trigger agenda_report_check before insert or update of agenda_event_id on documentations for each row execute function agenda_private.check_report();
create trigger agenda_report_link after insert on documentations for each row execute function agenda_private.link_report();
-- Access is limited to NEW agenda-linked reports; no old report becomes visible.
create policy agenda_linked_reports_read on documentations for select to authenticated using(deleted_at is null and agenda_event_id is not null and exists(select 1 from agenda_events e where e.id=agenda_event_id and (e.created_by=(select auth.uid()) or (select agenda_private.manager()))));
revoke all on all functions in schema agenda_private from public,anon,authenticated;
grant execute on function agenda_private.member(),agenda_private.manager(),agenda_private.save_event(jsonb),agenda_private.review_event(uuid,text,text,integer,uuid),agenda_private.staff() to authenticated;
revoke all on function public.agenda_context(),public.save_agenda_event(jsonb),public.review_agenda_event(uuid,text,text,integer,uuid),public.agenda_staff() from public,anon;
grant execute on function public.agenda_context(),public.save_agenda_event(jsonb),public.review_agenda_event(uuid,text,text,integer,uuid),public.agenda_staff() to authenticated;
-- Conflict counts do not disclose titles or owners of private pending requests.
create function agenda_private.conflicts(payload jsonb) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('time',count(*),'place',count(*) filter(where lower(btrim(e.location))=lower(btrim(payload->>'location'))),'uncertain',count(*) filter(where (e.slot='other')<>(payload->>'slot'='other')))
 from public.agenda_events e where agenda_private.member() and e.status in('pending','approved') and e.event_date=(payload->>'event_date')::date and e.id is distinct from nullif(payload->>'id','')::uuid and (case when e.slot='other' and payload->>'slot'='other' then e.starts_at<(payload->>'ends_at')::time and e.ends_at>(payload->>'starts_at')::time else e.slot=payload->>'slot' or e.slot='both' or payload->>'slot'='both' or e.slot='other' or payload->>'slot'='other' end)
$$;
create function public.agenda_conflicts(payload jsonb) returns jsonb language sql stable security invoker set search_path='' as $$select agenda_private.conflicts(payload)$$;
revoke all on function agenda_private.conflicts(jsonb),public.agenda_conflicts(jsonb) from public,anon;grant execute on function agenda_private.conflicts(jsonb),public.agenda_conflicts(jsonb) to authenticated;
