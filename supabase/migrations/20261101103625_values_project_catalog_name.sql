-- Rename the catalog identity, not historical report contents. Keep aliases writable.
create table documentation_private.values_project_rename_backup as
 select id,kind,name from public.school_tags where kind='project' and name in
 ('مشروع أثر التعليم في البيئة المدرسية','أثر التعليم في البيئة المدرسية','مشروع اثر تعليم في البيئة المدرسية');
alter table documentation_private.values_project_rename_backup enable row level security;
revoke all on documentation_private.values_project_rename_backup from public,anon,authenticated;
create table documentation_private.values_project_function_backup as
 select p.oid::regprocedure::text as signature,pg_get_functiondef(p.oid) as definition
 from pg_proc p where p.oid in('documentation_private.sync_tags()'::regprocedure,'public.documentation_tag_memberships()'::regprocedure);
alter table documentation_private.values_project_function_backup enable row level security;
revoke all on documentation_private.values_project_function_backup from public,anon,authenticated;
create function documentation_private.canonical_project_name(value text) returns text
 language sql immutable security invoker set search_path='' as $$
 select case when value in ('مشروع أثر التعليم في البيئة المدرسية','أثر التعليم في البيئة المدرسية','مشروع اثر تعليم في البيئة المدرسية')
 then 'مشروع أثر قيم التعلم في البيئة المدرسية' else value end
$$;
revoke all on function documentation_private.canonical_project_name(text) from public,anon;
grant execute on function documentation_private.canonical_project_name(text) to authenticated;
do $$begin
 if (select count(*) from public.school_tags where kind='project' and documentation_private.canonical_project_name(name)='مشروع أثر قيم التعلم في البيئة المدرسية')<>1 then
 raise exception 'Project identity requires review before rename';end if;
end$$;
update public.school_tags set name='مشروع أثر قيم التعلم في البيئة المدرسية'
 where kind='project' and documentation_private.canonical_project_name(name)='مشروع أثر قيم التعلم في البيئة المدرسية';
create or replace function documentation_private.sync_tags() returns trigger language plpgsql security definer set search_path='' as $$
declare category text;values_json jsonb;tag_name text;tid bigint;
begin
 delete from public.documentation_tags where documentation_id=new.id;
 for category in select unnest(array['project','committee']) loop
  values_json:=new.details->case category when 'project' then 'projects' else 'committees' end;
  if values_json is null then continue;end if;
  if jsonb_typeof(values_json)<>'array' or jsonb_array_length(values_json)>40 then raise exception 'اختيارات المشاريع واللجان غير صالحة.';end if;
  for tag_name in select jsonb_array_elements_text(values_json) loop
   if tag_name like 'غير مرتبط%' then continue;end if;
   if category='project' then tag_name:=documentation_private.canonical_project_name(tag_name);end if;
   select id into tid from public.school_tags where kind=category and name=tag_name;
   if not found then raise exception 'اسم المشروع أو اللجنة غير معتمد: %',tag_name;end if;
   insert into public.documentation_tags values(new.id,tid) on conflict do nothing;
  end loop;
 end loop;
 return new;
end$$;
create or replace function public.documentation_tag_memberships() returns table(documentation_id bigint,tag_id bigint)
 language sql stable security invoker set search_path='' as $$
 select l.documentation_id,l.tag_id from public.documentation_tags l
 union
 select d.id,t.id from public.documentations d join public.school_tags t on
 (t.kind='project' and (exists(select 1 from jsonb_array_elements_text(case when jsonb_typeof(d.details->'projects')='array' then d.details->'projects' else '[]'::jsonb end) n
 where documentation_private.canonical_project_name(n)=t.name)
 or exists(select 1 from unnest(documentation_private.legacy_tag_names(d.projects)) n where documentation_private.canonical_project_name(n)=t.name)))
 or (t.kind='committee' and (d.details->'committees' @> jsonb_build_array(t.name)
 or t.name=any(regexp_split_to_array(coalesce(d.committees,''),'\s*[•،\n]\s*'))))
$$;
-- Backfill links only for this project. Do not update documentations or their IDs.
insert into public.documentation_tags(documentation_id,tag_id)
 select d.id,t.id from public.documentations d cross join public.school_tags t
 where t.kind='project' and t.name='مشروع أثر قيم التعلم في البيئة المدرسية'
 and (exists(select 1 from jsonb_array_elements_text(case when jsonb_typeof(d.details->'projects')='array' then d.details->'projects' else '[]'::jsonb end) n
 where documentation_private.canonical_project_name(n)=t.name)
 or exists(select 1 from unnest(documentation_private.legacy_tag_names(d.projects)) n where documentation_private.canonical_project_name(n)=t.name))
 on conflict do nothing;
