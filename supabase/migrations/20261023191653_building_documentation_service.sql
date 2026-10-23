-- Separate source of truth. No copies in general documentation or competition statistics.
create table public.building_documentations(
 id uuid primary key,request_id uuid not null,created_by uuid not null references public.profiles(id),
 author_name text not null,title text not null check(length(btrim(title)) between 1 and 300),
 teacher_name text not null check(length(btrim(teacher_name)) between 1 and 300),
 description text not null default '' check(length(description)<=20000),results text not null default '' check(length(results)<=20000),
 area_selected boolean not null default false,committee_selected boolean not null default false,services_followup boolean not null default false,
 reference text not null unique default ('BD-'||to_char(now(),'YYYY')||'-'||lpad(nextval('building_private.reference_sequence')::text,6,'0')),
 version integer not null default 1,is_test boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),deleted_at timestamptz,delete_reason text,
 unique(created_by,request_id));
alter table public.building_documentations enable row level security;
revoke all on public.building_documentations from public,anon,authenticated,service_role;
grant select on public.building_documentations to authenticated;
create policy building_documentations_read on public.building_documentations for select to authenticated using(building_private.readable(created_by,deleted_at));
create index building_documentations_owner on public.building_documentations(created_by,created_at desc);
create function building_private.save_documentation(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();rid uuid:=(payload->>'id')::uuid;req uuid:=(payload->>'request_id')::uuid;o public.building_documentations;r public.building_documentations;prior record;
begin
 if not building_private.member() then raise exception 'هذه الخدمة لفريق متابعة المبنى المدرسي المخول فقط.' using errcode='42501';end if;
 if jsonb_typeof(payload)<>'object' or rid is null or req is null or payload-array['id','request_id','version','title','teacher_name','description','results','area_selected','committee_selected','services_followup','is_test']<>'{}'::jsonb then raise exception 'بيانات التوثيق غير صالحة.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));
 select * into prior from building_private.operations where actor_id=uid and request_id=req;
 if found then if prior.kind<>'building_documentation' or prior.payload<>payload then raise exception 'رقم حفظ مستخدم ببيانات مختلفة.';end if;return prior.result;end if;
 select * into o from public.building_documentations where id=rid for update;
 if o.id is not null and (o.deleted_at is not null or not(building_private.admin() or o.created_by=uid)) then raise exception 'لا تملكين صلاحية تعديل هذا التقرير.' using errcode='42501';end if;
 if o.id is not null and o.version is distinct from (payload->>'version')::integer then raise exception 'تغيّر التقرير؛ أعيدي فتح نسخته الأحدث.';end if;
 if length(btrim(coalesce(payload->>'title',''))) not between 1 and 300 or length(btrim(coalesce(payload->>'teacher_name',''))) not between 1 and 300 or length(coalesce(payload->>'description',''))>20000 or length(coalesce(payload->>'results',''))>20000 then raise exception 'اكتبي عنوان التقرير واسم المعلمة، وتحققي من طول النصوص.';end if;
 if o.id is null then
 insert into public.building_documentations(id,request_id,created_by,author_name,title,teacher_name,is_test)
 values(rid,req,uid,(select full_name from public.profiles where id=uid),payload->>'title',payload->>'teacher_name',coalesce((payload->>'is_test')::boolean,false));
 end if;
 update public.building_documentations set title=payload->>'title',teacher_name=payload->>'teacher_name',description=coalesce(payload->>'description',''),results=coalesce(payload->>'results',''),area_selected=coalesce((payload->>'area_selected')::boolean,false),committee_selected=coalesce((payload->>'committee_selected')::boolean,false),services_followup=coalesce((payload->>'services_followup')::boolean,false),version=coalesce(o.version,0)+1,updated_at=now() where id=rid returning * into r;
 perform building_private.log(r.id,'building_documentation',case when o.id is not null then to_jsonb(o) end,to_jsonb(r));
 insert into building_private.operations values(uid,req,'building_documentation',payload,to_jsonb(r));
 return to_jsonb(r);
end$$;
revoke all on function building_private.save_documentation(jsonb) from public,anon;
grant execute on function building_private.save_documentation(jsonb) to authenticated;
create function public.building_save_documentation(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select building_private.save_documentation(payload)$$;
revoke all on function public.building_save_documentation(jsonb) from public,anon;
grant execute on function public.building_save_documentation(jsonb) to authenticated;
create function building_private.remove_documentation(record_id uuid,removed boolean,expected_version integer,reason text) returns jsonb language plpgsql security definer set search_path='' as $$declare o public.building_documentations;r public.building_documentations;begin
 if not building_private.admin() then raise exception 'حذف التوثيق للإدارة العليا فقط.' using errcode='42501';end if;
 if btrim(coalesce(reason,''))='' or length(reason)>2000 or removed is null then raise exception 'يرجى كتابة سبب الإجراء.';end if;
 select * into o from public.building_documentations where id=record_id for update;
 if o.id is null or o.version is distinct from expected_version then raise exception 'أعيدي فتح التقرير الأحدث.';end if;
 update public.building_documentations set deleted_at=case when removed then now() else null end,delete_reason=reason,version=version+1,updated_at=now() where id=record_id returning * into r;
 perform building_private.log(r.id,case when removed then 'building_documentation_remove' else 'building_documentation_restore' end,to_jsonb(o),to_jsonb(r));return to_jsonb(r);
end$$;
revoke all on function building_private.remove_documentation(uuid,boolean,integer,text) from public,anon;
grant execute on function building_private.remove_documentation(uuid,boolean,integer,text) to authenticated;
create function public.building_remove_documentation(record_id uuid,removed boolean,expected_version integer,reason text) returns jsonb language sql security invoker set search_path='' as $$select building_private.remove_documentation(record_id,removed,expected_version,reason)$$;
revoke all on function public.building_remove_documentation(uuid,boolean,integer,text) from public,anon;
grant execute on function public.building_remove_documentation(uuid,boolean,integer,text) to authenticated;
