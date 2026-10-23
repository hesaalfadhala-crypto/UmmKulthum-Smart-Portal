-- Preserve every existing record, location, membership and policy. Only new free-text saves may have no site link.
insert into building_private.backups(purpose,snapshot)
select 'before_free_text_building_location',jsonb_build_object('save_function',pg_get_functiondef('building_private.save(jsonb)'::regprocedure),'records',coalesce((select jsonb_agg(to_jsonb(r)) from public.building_records r),'[]'::jsonb));
alter table public.building_records alter column location_id drop not null;
create or replace function building_private.save(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();rid uuid:=(payload->>'id')::uuid;req uuid:=(payload->>'request_id')::uuid;o public.building_records;r public.building_records;l record;prior record;rt text[];issues text[];ss text[];k text:=payload->>'kind';repeats text[];days integer;typed text;floor_row public.building_floors;registered public.building_locations;matches integer;match_id uuid;begin
 if not building_private.member() then raise exception 'لا تملكين صلاحية إنشاء النماذج.' using errcode='42501';end if;
 if rid is null or req is null or jsonb_typeof(payload)<>'object' or payload-ARRAY['id','request_id','version','kind','location_id','location_text','floor_id','location_type','grade','section','observed_at','ratings','issue_types','other_issue','description','priority','hazard','position','position_detail','notes','supervisors','files','is_test']<>'{}'::jsonb then raise exception 'بيانات الحفظ غير صالحة.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));
 select * into prior from building_private.operations x where x.actor_id=uid and x.request_id=req;
 if found then if prior.kind<>'save' or prior.payload<>payload then raise exception 'أعيد استخدام رقم الحفظ ببيانات مختلفة.';end if;return prior.result;end if;
 select * into o from public.building_records where id=rid for update;
 if o.id is not null and (o.deleted_at is not null or not (building_private.admin() or o.created_by=uid and o.status='new')) then raise exception 'لا تملكين صلاحية تعديل هذا التقرير في حالته الحالية.' using errcode='42501';end if;
 if o.id is not null and o.version is distinct from (payload->>'version')::integer then raise exception 'تغير التقرير؛ أعيدي فتح النسخة الأحدث.';end if;
 if k is null or k not in('cleanliness','supplies','toilet_maintenance','building_maintenance') or o.id is not null and o.kind<>k then raise exception 'نوع النموذج غير صالح.';end if;
 if payload ? 'location_text' then
 typed:=payload->>'location_text';
 if jsonb_typeof(payload->'location_text') is distinct from 'string' or btrim(coalesce(typed,''))='' or length(typed)>500 then raise exception 'يرجى كتابة تحديد الموقع (حتى 500 حرف).';end if;
 select * into floor_row from public.building_floors where id=(payload->>'floor_id')::uuid and (active or id=nullif(o.location_snapshot->>'floor_id','')::uuid);
 if not found then raise exception 'اختاري الطابق.';end if;
 if coalesce(payload->>'location_type','') not in('toilet','classroom','corridor','lab','office','hall','other') or (k<>'building_maintenance' and payload->>'location_type'<>'toilet') or (k='building_maintenance' and payload->>'location_type'='toilet') then raise exception 'نوع الموقع غير مناسب للنموذج.';end if;
 if length(coalesce(payload->>'grade',''))>100 or length(coalesce(payload->>'section',''))>100 then raise exception 'الصف أو الشعبة غير صالحين.';end if;
 -- Exact name + floor + type only. Never trust a client-supplied ID, infer aliases, or create a location.
 select count(*)::int,(array_agg(loc.id))[1] into matches,match_id from public.building_locations loc
 where loc.floor_id=floor_row.id and loc.type=payload->>'location_type' and btrim(loc.name)=btrim(typed) and (loc.active or loc.id=o.location_id);
 if matches<>1 then match_id:=null;end if;
 if o.id is not null and o.location_id is not null and typed is not distinct from o.location_snapshot->>'name' and floor_row.id::text=o.location_snapshot->>'floor_id' and payload->>'location_type'=o.location_snapshot->>'type' then match_id:=o.location_id;end if;
 if match_id is not null then select * into registered from public.building_locations where id=match_id;end if;
 select match_id id,floor_row.id floor_id,floor_row.name floor,payload->>'location_type' type,typed name,
 case when payload->>'location_type'='classroom' then coalesce(nullif(payload->>'grade',''),registered.grade,'') else '' end grade,
 case when payload->>'location_type'='classroom' then coalesce(nullif(payload->>'section',''),registered.section,'') else '' end section into l;
 else
 select loc.*,f.name floor into l from public.building_locations loc join public.building_floors f on f.id=loc.floor_id where loc.id=(payload->>'location_id')::uuid and (loc.active and f.active or loc.id=o.location_id);
 if not found or (k<>'building_maintenance' and l.type<>'toilet') or (k='building_maintenance' and l.type='toilet') then raise exception 'اختاري موقعًا مسجلًا مناسبًا للنموذج.';end if;
 end if;
 if (payload->>'observed_at')::timestamptz is null or extract(year from (payload->>'observed_at')::timestamptz) not between 2000 and 2100 then raise exception 'تاريخ المتابعة غير صالح.';end if;
 rt:=array(select jsonb_array_elements_text(coalesce(payload->'ratings','[]')));issues:=array(select distinct jsonb_array_elements_text(coalesce(payload->'issue_types','[]')));ss:=array(select distinct jsonb_array_elements_text(coalesce(payload->'supervisors','[]')));
 if not ss<@ARRAY['assistant','aisha','hiba','services'] then raise exception 'اختيار الإشراف غير صالح.';end if;
 if k='cleanliness' and (cardinality(rt)<>4 or not rt<@ARRAY['excellent','good','poor']) or k='supplies' and(cardinality(rt)<>4 or not rt<@ARRAY['available','missing']) or k in('cleanliness','supplies') and cardinality(issues)>0 then raise exception 'اختاري تقييمًا واحدًا لكل بند من البنود الأربعة.';end if;
 if k='toilet_maintenance' and(cardinality(issues)<>1 or not issues<@ARRAY['fault','leak','lock','other']) or k='building_maintenance' and(cardinality(issues)=0 or not issues<@ARRAY['curtains','door','window','lock','handle','ac','light','socket','leak','furniture','board','other']) then raise exception 'اختاري نوع العطل.';end if;
 if k in('toilet_maintenance','building_maintenance') and cardinality(rt)>0 then raise exception 'التقييم غير مناسب لطلب الصيانة.';end if;
 if 'other'=any(issues) and btrim(coalesce(payload->>'other_issue',''))='' then raise exception 'يرجى تحديد نوع المشكلة الأخرى.';end if;
 if l.type='corridor' and (coalesce(payload->>'position','') not in('start','middle','end','near','other') or payload->>'position' in('near','other') and btrim(coalesce(payload->>'position_detail',''))='') then raise exception 'حددي موقع العطل داخل الممر.';end if;
 if length(coalesce(payload->>'description',''))>20000 or length(coalesce(payload->>'notes',''))>10000 or length(coalesce(payload->>'other_issue',''))>1000 or length(coalesce(payload->>'position_detail',''))>1000 or coalesce(payload->>'priority','normal') not in('normal','urgent') then raise exception 'التفاصيل أو الأولوية غير صالحة.';end if;
 perform building_private.validate_files(coalesce(payload->'files','[]'),o.files,rid);
 if o.id is null then
 insert into public.building_records(id,request_id,created_by,author_name,kind,location_id,location_snapshot,observed_at,is_test)
 values(rid,req,uid,(select full_name from public.profiles where id=uid),k,l.id,to_jsonb(l),(payload->>'observed_at')::timestamptz,coalesce((payload->>'is_test')::boolean,false));end if;
 update public.building_records set location_id=l.id,location_snapshot=to_jsonb(l),observed_at=(payload->>'observed_at')::timestamptz,ratings=rt,issue_types=issues,other_issue=case when 'other'=any(issues) then payload->>'other_issue' else '' end,description=coalesce(payload->>'description',''),priority=coalesce(payload->>'priority','normal'),hazard=coalesce((payload->>'hazard')::boolean,false),position=case when l.type='corridor' then payload->>'position' else '' end,position_detail=case when l.type='corridor' and payload->>'position' in('near','other') then payload->>'position_detail' else '' end,notes=coalesce(payload->>'notes',''),supervisors=ss,files=coalesce(payload->'files','[]'),version=coalesce(o.version,0)+1,updated_at=now() where id=rid returning * into r;
 perform building_private.log(r.id,'report',case when o.id is not null then to_jsonb(o) end,to_jsonb(r));
 if o.id is null and k in('toilet_maintenance','building_maintenance') then
 perform building_private.notify(r,'new',case when r.priority='urgent' then 'طلب صيانة عاجل — ' else 'طلب صيانة جديد — ' end||l.name);
 select repeat_days into days from public.building_settings;
 select array_agg(issue) into repeats from unnest(issues) issue where (select count(*) from public.building_records b where b.location_id=r.location_id and b.deleted_at is null and b.is_test=r.is_test and issue=any(b.issue_types) and (issue<>'other' or building_private.key(b.other_issue)=building_private.key(r.other_issue)) and b.observed_at>=now()-make_interval(days=>days) and b.observed_at<=now())>=2;
 if cardinality(repeats)>0 then perform building_private.notify(r,'repeat','تكرار بلاغات صيانة في '||l.name);end if;end if;
 if k='cleanliness' and 'poor'=any(rt) and (o.id is null or rt is distinct from o.ratings or (l.id is distinct from o.location_id or l.name is distinct from o.location_snapshot->>'name' or to_jsonb(l)->>'floor_id' is distinct from o.location_snapshot->>'floor_id')) then perform building_private.notify(r,'poor-'||r.version,'تقييم نظافة ضعيف — '||l.name);end if;
 if k='supplies' and 'missing'=any(rt) and (o.id is null or rt is distinct from o.ratings or (l.id is distinct from o.location_id or l.name is distinct from o.location_snapshot->>'name' or to_jsonb(l)->>'floor_id' is distinct from o.location_snapshot->>'floor_id')) then perform building_private.notify(r,'missing-'||r.version,'غير متوفر: '||array_to_string(array(select (ARRAY['توفر الصابون','توفر المحارم الورقية','توفر أدوات التنظيف للعاملات','فحص مخزن المواد بشكل دوري'])[n] from generate_subscripts(rt,1) n where rt[n]='missing'),'، ')||' — '||l.name);end if;
 insert into building_private.operations values(uid,req,'save',payload,to_jsonb(r));return to_jsonb(r);end$$;
