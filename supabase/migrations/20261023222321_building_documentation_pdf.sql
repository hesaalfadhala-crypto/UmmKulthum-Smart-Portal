create or replace function building_private.save_documentation(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();rid uuid:=(payload->>'id')::uuid;req uuid:=(payload->>'request_id')::uuid;o public.building_documentations;r public.building_documentations;prior record;
begin
 if not building_private.member() then raise exception 'هذه الخدمة لفريق متابعة المبنى المدرسي المخول فقط.' using errcode='42501';end if;
 if jsonb_typeof(payload)<>'object' or rid is null or req is null or payload-array['id','request_id','version','title','teacher_name','description','results','area_selected','committee_selected','services_followup','is_test','files']<>'{}'::jsonb then raise exception 'بيانات التوثيق غير صالحة.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));
 select * into prior from building_private.operations where actor_id=uid and request_id=req;
 if found then if prior.kind<>'building_documentation' or prior.payload<>payload then raise exception 'رقم حفظ مستخدم ببيانات مختلفة.';end if;return prior.result;end if;
 select * into o from public.building_documentations where id=rid for update;
 if o.id is not null and (o.deleted_at is not null or not(building_private.admin() or o.created_by=uid)) then raise exception 'لا تملكين صلاحية تعديل هذا التقرير.' using errcode='42501';end if;
 if o.id is not null and o.version is distinct from (payload->>'version')::integer then raise exception 'تغيّر التقرير؛ أعيدي فتح نسخته الأحدث.';end if;
 if length(btrim(coalesce(payload->>'title',''))) not between 1 and 300 or length(btrim(coalesce(payload->>'teacher_name',''))) not between 1 and 300 or length(coalesce(payload->>'description',''))>20000 or length(coalesce(payload->>'results',''))>20000 then raise exception 'اكتبي عنوان التقرير واسم المعلمة، وتحققي من طول النصوص.';end if;
 perform building_private.validate_files(coalesce(payload->'files',o.files,'[]'::jsonb),o.files,rid);
 if o.id is null then
 insert into public.building_documentations(id,request_id,created_by,author_name,title,teacher_name,is_test)
 values(rid,req,uid,(select full_name from public.profiles where id=uid),payload->>'title',payload->>'teacher_name',coalesce((payload->>'is_test')::boolean,false));
 end if;
 update public.building_documentations set title=payload->>'title',teacher_name=payload->>'teacher_name',description=coalesce(payload->>'description',''),results=coalesce(payload->>'results',''),area_selected=coalesce((payload->>'area_selected')::boolean,false),committee_selected=coalesce((payload->>'committee_selected')::boolean,false),services_followup=coalesce((payload->>'services_followup')::boolean,false),files=coalesce(payload->'files',o.files,'[]'::jsonb),version=coalesce(o.version,0)+1,updated_at=now() where id=rid returning * into r;
 perform building_private.log(r.id,'building_documentation',case when o.id is not null then to_jsonb(o) end,to_jsonb(r));
 insert into building_private.operations values(uid,req,'building_documentation',payload,to_jsonb(r));
 return to_jsonb(r);
end$$;