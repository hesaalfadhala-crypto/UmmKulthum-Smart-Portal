create table public.radio_weeks(start_date date primary key check(extract(dow from start_date)=0),created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table public.radio_segments(week_start date not null references public.radio_weeks(start_date),day_index integer not null check(day_index between 0 and 4),slot integer not null check(slot in(1,2)),title text not null default '' check(length(title)<=600),department text not null default '' check(length(department)<=180),responsible_ids uuid[] not null default '{}',responsible_names text[] not null default '{}',created_by uuid not null references public.profiles(id),version integer not null default 1,updated_at timestamptz not null default now(),primary key(week_start,day_index,slot));
alter table public.radio_weeks enable row level security;
alter table public.radio_segments enable row level security;
revoke all on public.radio_weeks,public.radio_segments from public,anon,authenticated;
grant select on public.radio_weeks,public.radio_segments to authenticated;
create policy radio_weeks_read on public.radio_weeks for select to authenticated using((select agenda_private.member()));
create policy radio_segments_read on public.radio_segments for select to authenticated using((select agenda_private.member()));
create function agenda_private.save_radio(week_date date,entries jsonb) returns void language plpgsql security definer set search_path='' as $$
declare e jsonb;old public.radio_segments;ids uuid[];names text[];uid uuid:=auth.uid();
begin
if not agenda_private.member() then raise exception 'يلزم حساب المدرسة';end if;
if week_date is null or extract(dow from week_date)<>0 or jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries)>10 then raise exception 'بيانات الأسبوع غير صالحة';end if;
perform pg_advisory_xact_lock(hashtextextended('radio:'||week_date::text,0));
insert into public.radio_weeks(start_date,created_by) values(week_date,uid) on conflict do nothing;
for e in select value from jsonb_array_elements(entries) loop
if (e->>'day_index')::integer not between 0 and 4 or (e->>'slot')::integer not in(1,2) or e->>'day_index' is null or e->>'slot' is null then raise exception 'يسمح بفقرتين فقط لكل يوم';end if;
select * into old from public.radio_segments where week_start=week_date and day_index=(e->>'day_index')::int and slot=(e->>'slot')::int for update;
if found and (old.created_by<>uid or old.version is distinct from (e->>'version')::int) then raise exception 'لا يمكنك تعديل فقرة زميلتك أو تغيرت النسخة؛ أعيدي تحميل الجدول';end if;
if old.week_start is null and coalesce((e->>'version')::int,0)<>0 then raise exception 'تغيرت الفقرة؛ أعيدي تحميل الجدول';end if;
if jsonb_typeof(e->'responsible_ids') is distinct from 'array' or jsonb_array_length(e->'responsible_ids')>150 then raise exception 'اختاري المسؤولات';end if;
select coalesce(array_agg(distinct value::uuid),'{}') into ids from jsonb_array_elements_text(e->'responsible_ids');
select coalesce(array_agg(s.full_name order by s.full_name),'{}') into names from public.agenda_staff() s where s.id=any(ids);
if cardinality(names)<>cardinality(ids) then raise exception 'إحدى المسؤولات غير موجودة';end if;
if coalesce(btrim(e->>'title'),'')<>'' and (coalesce(btrim(e->>'department'),'')='' or cardinality(ids)=0) then raise exception 'اختاري القسم والمسؤولات للفقرة المستخدمة';end if;
if coalesce(btrim(e->>'title'),'')='' and (coalesce(btrim(e->>'department'),'')<>'' or cardinality(ids)>0) then raise exception 'اكتبي عنوان الفقرة أو اتركي بياناتها كلها فارغة';end if;
insert into public.radio_segments(week_start,day_index,slot,title,department,responsible_ids,responsible_names,created_by) values(week_date,(e->>'day_index')::int,(e->>'slot')::int,coalesce(btrim(e->>'title'),''),coalesce(btrim(e->>'department'),''),ids,names,uid) on conflict(week_start,day_index,slot) do update set title=excluded.title,department=excluded.department,responsible_ids=excluded.responsible_ids,responsible_names=excluded.responsible_names,version=public.radio_segments.version+1,updated_at=now();
end loop;
end $$;
create function public.save_radio_week(week_date date,entries jsonb) returns void language sql security invoker set search_path='' as $$select agenda_private.save_radio(week_date,entries)$$;
revoke all on function agenda_private.save_radio(date,jsonb),public.save_radio_week(date,jsonb) from public,anon;
grant execute on function agenda_private.save_radio(date,jsonb),public.save_radio_week(date,jsonb) to authenticated;
