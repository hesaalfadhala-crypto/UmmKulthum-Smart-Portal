-- Independent school-building service. No writes to documentation, profiles or existing services.
create schema building_private;
revoke all on schema building_private from public,anon;
grant usage on schema building_private to authenticated;
create table building_private.admins(user_id uuid primary key references public.profiles(id));
create table building_private.audit(id bigint generated always as identity primary key,object_id uuid,kind text not null,actor_id uuid references public.profiles(id),before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
create table building_private.operations(actor_id uuid not null,request_id uuid not null,kind text not null,payload jsonb not null,result jsonb not null,primary key(actor_id,request_id));
create table building_private.backups(id bigint generated always as identity primary key,created_at timestamptz not null default now(),purpose text not null,snapshot jsonb not null);
create table public.building_members(user_id uuid primary key references public.profiles(id),role text not null check(role in('admin','chair','deputy','oversight','member')),active boolean not null default true);
create table public.building_settings(id boolean primary key default true check(id),repeat_days integer not null default 30 check(repeat_days between 1 and 365),notifications_enabled boolean not null default false);
insert into public.building_settings(id) values(true);
create function building_private.key(value text) returns text language sql immutable set search_path='' as $$select lower(regexp_replace(translate(regexp_replace(coalesce(value,''),'[ـًٌٍَُِّْ]','','g'),'أإآى٠١٢٣٤٥٦٧٨٩','اااي0123456789'),'[[:space:][:punct:]]+','','g'))$$;
create table public.building_floors(id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 100),canonical_name text generated always as(building_private.key(name)) stored unique,active boolean not null default true);
create table public.building_locations(id uuid primary key default gen_random_uuid(),floor_id uuid not null references public.building_floors(id),type text not null check(type in('toilet','classroom','corridor','lab','office','hall','other')),name text not null check(length(btrim(name)) between 1 and 200),grade text not null default '',section text not null default '',description text not null default '' check(length(description)<=2000),canonical_name text generated always as(building_private.key(case when type='classroom' then grade||'/'||section else name end)) stored,active boolean not null default true,unique(floor_id,type,canonical_name),check(type<>'classroom' or (btrim(grade)<>'' and btrim(section)<>'')));
create sequence building_private.reference_sequence;
create table public.building_records(id uuid primary key,request_id uuid not null,created_by uuid not null references public.profiles(id),author_name text not null,kind text not null check(kind in('cleanliness','supplies','toilet_maintenance','building_maintenance')),location_id uuid not null references public.building_locations(id),location_snapshot jsonb not null,reference text not null unique default ('BM-'||to_char(now(),'YYYY')||'-'||lpad(nextval('building_private.reference_sequence')::text,6,'0')),observed_at timestamptz not null,ratings text[] not null default '{}',issue_types text[] not null default '{}',other_issue text not null default '',description text not null default '',priority text not null default 'normal' check(priority in('normal','urgent')),hazard boolean not null default false,position text not null default '',position_detail text not null default '',notes text not null default '',supervisors text[] not null default '{}',files jsonb not null default '[]',repair_files jsonb not null default '[]',status text not null default 'new' check(status in('new','progress','repaired')),action_taken text not null default '',repair_date date,followup_notes text not null default '',is_test boolean not null default false,version integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),deleted_at timestamptz,delete_reason text,unique(created_by,request_id));
create index building_audit_object on building_private.audit(object_id,id desc);
create index building_locations_floor on public.building_locations(floor_id,type);
create index building_records_owner on public.building_records(created_by,created_at desc);
create index building_records_location on public.building_records(location_id,observed_at desc) where deleted_at is null;
create index building_records_status on public.building_records(status,priority) where deleted_at is null;
create index building_files_refs on public.building_records using gin(files jsonb_path_ops);
create index building_repair_files_refs on public.building_records using gin(repair_files jsonb_path_ops);
create table public.building_notifications(id uuid primary key default gen_random_uuid(),recipient_id uuid not null references public.profiles(id),record_id uuid not null references public.building_records(id),event_key text not null,title text not null,created_at timestamptz not null default now(),read_at timestamptz,unique(recipient_id,record_id,event_key));
create index building_notices_recipient on public.building_notifications(recipient_id,created_at desc);
create function building_private.role() returns text language sql stable security definer set search_path='' as $$select case when exists(select 1 from building_private.admins a where a.user_id=m.user_id) then 'admin' else m.role end from public.building_members m where m.user_id=auth.uid() and m.active$$;
create function building_private.member() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and building_private.role() is not null$$;
create function building_private.admin() returns boolean language sql stable security definer set search_path='' as $$select coalesce(building_private.role()='admin',false)$$;
create function building_private.all_records() returns boolean language sql stable security definer set search_path='' as $$select coalesce(building_private.role() in('admin','chair','deputy','oversight'),false)$$;
create function building_private.followup() returns boolean language sql stable security definer set search_path='' as $$select coalesce(building_private.role() in('admin','chair','deputy'),false)$$;
create function building_private.can_stats() returns boolean language sql stable security definer set search_path='' as $$select coalesce(building_private.role() in('admin','chair'),false)$$;
create function building_private.readable(owner_id uuid,deleted timestamptz) returns boolean language sql stable security definer set search_path='' as $$select building_private.member() and (deleted is null or building_private.admin()) and (owner_id=auth.uid() or building_private.all_records())$$;
create function building_private.context() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not building_private.member() then raise exception 'هذه الخدمة للفريق المخول فقط.' using errcode='42501';end if;
 return jsonb_build_object('user_id',auth.uid(),'full_name',(select full_name from public.profiles where id=auth.uid()),'role',building_private.role(),'admin',building_private.admin(),'all_records',building_private.all_records(),'followup',building_private.followup(),'statistics',building_private.can_stats(),'repeat_days',(select repeat_days from public.building_settings),'notifications_enabled',(select notifications_enabled from public.building_settings));end$$;
create function building_private.log(object_id uuid,kind text,before_data jsonb,after_data jsonb) returns void language sql security invoker set search_path='' as $$insert into building_private.audit(object_id,kind,actor_id,before_data,after_data) values(object_id,kind,auth.uid(),before_data,after_data)$$;
create function building_private.validate_files(files jsonb,previous jsonb,record_id uuid) returns void language plpgsql security definer set search_path='' as $$declare f jsonb;begin
 if jsonb_typeof(files) is distinct from 'array' or jsonb_array_length(files)>15 then raise exception 'المرفقات غير صالحة.';end if;
 if (select count(*) from jsonb_array_elements(files) x where x->>'kind'='photo')>10 or (select count(*) from jsonb_array_elements(files) x where x->>'kind'='pdf')>5 or (select count(distinct x->>'path') from jsonb_array_elements(files) x)<>jsonb_array_length(files) then raise exception 'عدد المرفقات أو تكرارها غير صالح.';end if;
 for f in select * from jsonb_array_elements(files) loop
 if jsonb_typeof(f)<>'object' or f-ARRAY['bucket','path','name','kind']<>'{}'::jsonb or f->>'bucket' is distinct from 'school-building-files' or coalesce(f->>'kind','') not in('photo','pdf') or length(coalesce(f->>'name','')) not between 1 and 250 then raise exception 'مرجع مرفق غير صالح.';end if;
 if not coalesce(previous,'[]'::jsonb) @> jsonb_build_array(f) then
 if f->>'path' !~ ('^'||auth.uid()::text||'/'||record_id::text||'/[0-9a-f-]{36}\.'||case when f->>'kind'='pdf' then 'pdf' else 'jpg' end||'$') or not exists(select 1 from storage.objects o where o.bucket_id='school-building-files' and o.name=f->>'path' and coalesce(o.owner_id,o.owner::text)=auth.uid()::text and o.metadata->>'mimetype'=case when f->>'kind'='pdf' then 'application/pdf' else 'image/jpeg' end and (o.metadata->>'size')::bigint between 1 and 8388608) then raise exception 'لم يكتمل رفع المرفق أو لا تملكينه.';end if;
 end if;end loop;end$$;
create function building_private.notify(r public.building_records,event_key text,title text,owner_only boolean default false) returns void language plpgsql security definer set search_path='' as $$begin
 if r.is_test or not (select notifications_enabled from public.building_settings) then return;end if;
 insert into public.building_notifications(recipient_id,record_id,event_key,title)
 select m.user_id,r.id,event_key,title from public.building_members m where m.active and case when owner_only then m.user_id=r.created_by else m.role in('admin','chair','deputy','oversight') end
 on conflict do nothing;end$$;
create function building_private.save(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();rid uuid:=(payload->>'id')::uuid;req uuid:=(payload->>'request_id')::uuid;o public.building_records;r public.building_records;l record;prior record;rt text[];issues text[];ss text[];k text:=payload->>'kind';repeats text[];days integer;begin
 if not building_private.member() then raise exception 'لا تملكين صلاحية إنشاء النماذج.' using errcode='42501';end if;
 if rid is null or req is null or jsonb_typeof(payload)<>'object' or payload-ARRAY['id','request_id','version','kind','location_id','observed_at','ratings','issue_types','other_issue','description','priority','hazard','position','position_detail','notes','supervisors','files','is_test']<>'{}'::jsonb then raise exception 'بيانات الحفظ غير صالحة.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||req::text,0));
 select * into prior from building_private.operations x where x.actor_id=uid and x.request_id=req;
 if found then if prior.kind<>'save' or prior.payload<>payload then raise exception 'أعيد استخدام رقم الحفظ ببيانات مختلفة.';end if;return prior.result;end if;
 select * into o from public.building_records where id=rid for update;
 if o.id is not null and (o.deleted_at is not null or not (building_private.admin() or o.created_by=uid and o.status='new')) then raise exception 'لا تملكين صلاحية تعديل هذا التقرير في حالته الحالية.' using errcode='42501';end if;
 if o.id is not null and o.version is distinct from (payload->>'version')::integer then raise exception 'تغير التقرير؛ أعيدي فتح النسخة الأحدث.';end if;
 if k is null or k not in('cleanliness','supplies','toilet_maintenance','building_maintenance') or o.id is not null and o.kind<>k then raise exception 'نوع النموذج غير صالح.';end if;
 select loc.*,f.name floor into l from public.building_locations loc join public.building_floors f on f.id=loc.floor_id where loc.id=(payload->>'location_id')::uuid and (loc.active and f.active or loc.id=o.location_id);
 if not found or (k<>'building_maintenance' and l.type<>'toilet') or (k='building_maintenance' and l.type='toilet') then raise exception 'اختاري موقعًا مسجلًا مناسبًا للنموذج.';end if;
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
 if k='cleanliness' and 'poor'=any(rt) and (o.id is null or rt is distinct from o.ratings or l.id<>o.location_id) then perform building_private.notify(r,'poor-'||r.version,'تقييم نظافة ضعيف — '||l.name);end if;
 if k='supplies' and 'missing'=any(rt) and (o.id is null or rt is distinct from o.ratings or l.id<>o.location_id) then perform building_private.notify(r,'missing-'||r.version,'غير متوفر: '||array_to_string(array(select (ARRAY['توفر الصابون','توفر المحارم الورقية','توفر أدوات التنظيف للعاملات','فحص مخزن المواد بشكل دوري'])[n] from generate_subscripts(rt,1) n where rt[n]='missing'),'، ')||' — '||l.name);end if;
 insert into building_private.operations values(uid,req,'save',payload,to_jsonb(r));return to_jsonb(r);end$$;
create function building_private.follow(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare o public.building_records;r public.building_records;prior record;req uuid:=(payload->>'request_id')::uuid;begin
 if not building_private.followup() then raise exception 'تحديث حالة الصيانة للمسؤولات المخولات فقط.' using errcode='42501';end if;
 if req is null or payload-ARRAY['id','request_id','version','status','action_taken','repair_date','followup_notes','repair_files']<>'{}'::jsonb then raise exception 'بيانات المتابعة غير صالحة.';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||req::text,0));select * into prior from building_private.operations where actor_id=auth.uid() and request_id=req;if found then if prior.kind<>'follow' or prior.payload<>payload then raise exception 'رقم متابعة مكرر ببيانات مختلفة.';end if;return prior.result;end if;
 select * into o from public.building_records where id=(payload->>'id')::uuid for update;
 if o.id is null or o.deleted_at is not null or o.kind not in('toilet_maintenance','building_maintenance') then raise exception 'طلب الصيانة غير متاح.';end if;
 if o.version is distinct from (payload->>'version')::integer then raise exception 'تغير الطلب؛ افتحي النسخة الأحدث.';end if;
 if coalesce(payload->>'status','') not in('new','progress','repaired') or payload->>'status'='repaired' and (nullif(payload->>'repair_date','') is null or btrim(coalesce(payload->>'action_taken',''))='') or length(coalesce(payload->>'action_taken',''))>20000 or length(coalesce(payload->>'followup_notes',''))>10000 then raise exception 'حددي الحالة والإجراء وتاريخ الإصلاح عند إغلاق الطلب.';end if;
 perform building_private.validate_files(coalesce(payload->'repair_files','[]'),o.repair_files,o.id);
 update public.building_records set status=payload->>'status',action_taken=coalesce(payload->>'action_taken',''),repair_date=case when payload->>'status'='repaired' then (payload->>'repair_date')::date end,followup_notes=coalesce(payload->>'followup_notes',''),repair_files=coalesce(payload->'repair_files','[]'),version=version+1,updated_at=now() where id=o.id returning * into r;
 perform building_private.log(r.id,'followup',to_jsonb(o),to_jsonb(r));
 if o.status<>r.status then perform building_private.notify(r,'state-'||r.version,case when r.status='repaired' then 'تم إصلاح طلبكِ — ' else 'تحديث حالة طلبكِ — ' end||r.reference,true);end if;
 insert into building_private.operations values(auth.uid(),req,'follow',payload,to_jsonb(r));return to_jsonb(r);end$$;
create function building_private.remove(record_id uuid,removed boolean,expected_version integer,reason text) returns void language plpgsql security definer set search_path='' as $$declare o public.building_records;r public.building_records;begin
 if not building_private.admin() then raise exception 'حذف السجلات واستعادتها للإدارة العليا فقط.' using errcode='42501';end if;
 select * into o from public.building_records where id=record_id for update;if o.id is null or o.version<>expected_version then raise exception 'السجل تغير أو غير موجود.';end if;
 if btrim(coalesce(reason,''))='' or length(reason)>1000 then raise exception 'اكتبي سبب الإجراء.';end if;
 update public.building_records set deleted_at=case when removed then now() end,delete_reason=reason,version=version+1,updated_at=now() where id=record_id returning * into r;perform building_private.log(record_id,case when removed then 'delete' else 'restore' end,to_jsonb(o),to_jsonb(r));end$$;
create function building_private.manage_location(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare rid uuid:=coalesce(nullif(payload->>'id','')::uuid,gen_random_uuid());before_value jsonb;result jsonb;begin
 if not building_private.admin() then raise exception 'إدارة المواقع للإدارة العليا فقط.' using errcode='42501';end if;
 if payload->>'entity'='floor' then
 select to_jsonb(f) into before_value from public.building_floors f where id=rid;
 insert into public.building_floors(id,name,active) values(rid,payload->>'name',coalesce((payload->>'active')::boolean,true)) on conflict(id) do update set name=excluded.name,active=excluded.active returning to_jsonb(building_floors) into result;
 elsif payload->>'entity'='location' then
 if length(coalesce(payload->>'grade',''))>100 or length(coalesce(payload->>'section',''))>100 then raise exception 'الصف أو الشعبة غير صالحين.';end if;
 select to_jsonb(l) into before_value from public.building_locations l where id=rid;
 insert into public.building_locations(id,floor_id,type,name,grade,section,description,active) values(rid,(payload->>'floor_id')::uuid,payload->>'type',payload->>'name',coalesce(payload->>'grade',''),coalesce(payload->>'section',''),coalesce(payload->>'description',''),coalesce((payload->>'active')::boolean,true)) on conflict(id) do update set floor_id=excluded.floor_id,type=excluded.type,name=excluded.name,grade=excluded.grade,section=excluded.section,description=excluded.description,active=excluded.active returning to_jsonb(building_locations) into result;
 else raise exception 'نوع الموقع غير صالح.';end if;
 perform building_private.log(rid,'location',before_value,result);return result;end$$;
create function building_private.manage_member(uid uuid,new_role text,enabled boolean,reason text) returns void language plpgsql security definer set search_path='' as $$declare o jsonb;begin
 if not building_private.admin() then raise exception 'إدارة صلاحيات الفريق للإدارة العليا فقط.' using errcode='42501';end if;
 if exists(select 1 from building_private.admins where user_id=uid) then raise exception 'لا يمكن تغيير الإدارة العليا من هذه الشاشة.';end if;
 if new_role not in('chair','deputy','oversight','member') or not exists(select 1 from public.profiles where id=uid) or btrim(coalesce(reason,''))='' then raise exception 'راجعي الحساب والتكليف وسبب التغيير.';end if;
 select to_jsonb(m) into o from public.building_members m where user_id=uid;
 insert into public.building_members values(uid,new_role,enabled) on conflict(user_id) do update set role=excluded.role,active=excluded.active;
 if o is distinct from jsonb_build_object('user_id',uid,'role',new_role,'active',enabled) then perform building_private.log(uid,'membership',o,jsonb_build_object('user_id',uid,'role',new_role,'active',enabled,'reason',reason));end if;end$$;
create function building_private.settings(days integer,notifications boolean) returns void language plpgsql security definer set search_path='' as $$declare oldrow jsonb;begin if not building_private.admin() then raise exception 'الإعدادات للإدارة العليا فقط.' using errcode='42501';end if;select to_jsonb(s) into oldrow from public.building_settings s;update public.building_settings set repeat_days=days,notifications_enabled=notifications;perform building_private.log(null,'settings',oldrow,jsonb_build_object('repeat_days',days,'notifications_enabled',notifications));end$$;
create function building_private.staff() returns jsonb language plpgsql stable security definer set search_path='' as $$begin if not building_private.admin() then raise exception 'لا تملكين صلاحية عرض الحسابات.' using errcode='42501';end if;return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'job_title',p.job_title,'role',m.role,'active',m.active) order by p.full_name) from public.profiles p left join public.building_members m on m.user_id=p.id),'[]');end$$;
create function building_private.history(record_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin if not exists(select 1 from public.building_records r where r.id=record_id and building_private.readable(r.created_by,r.deleted_at)) then raise exception 'السجل غير متاح.' using errcode='42501';end if;return coalesce((select jsonb_agg(jsonb_build_object('kind',a.kind,'created_at',a.created_at,'actor',(select full_name from public.profiles where id=a.actor_id),'status',a.after_data->>'status','action_taken',a.after_data->>'action_taken','repair_date',a.after_data->>'repair_date','notes',a.after_data->>'followup_notes') order by a.id desc) from building_private.audit a where a.object_id=record_id and a.kind in('report','followup','delete','restore')),'[]');end$$;
create function building_private.mark_read(notice_id uuid) returns void language sql security definer set search_path='' as $$update public.building_notifications set read_at=coalesce(read_at,now()) where id=notice_id and recipient_id=auth.uid() and building_private.member()$$;
create function building_private.storage_read(path text) returns boolean language sql stable security definer set search_path='' as $$select building_private.member() and ((storage.foldername(path))[1]=auth.uid()::text or exists(select 1 from public.building_records r where building_private.readable(r.created_by,r.deleted_at) and (r.files @> jsonb_build_array(jsonb_build_object('path',path)) or r.repair_files @> jsonb_build_array(jsonb_build_object('path',path)))))$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('school-building-files','school-building-files',false,8388608,array['image/jpeg','application/pdf']);
create policy building_upload on storage.objects for insert to authenticated with check(bucket_id='school-building-files' and (select building_private.member()) and (storage.foldername(name))[1]=(select auth.uid())::text and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|pdf)$');
create policy building_file_read on storage.objects for select to authenticated using(bucket_id='school-building-files' and building_private.storage_read(name));
-- All mutation APIs validate identity and role in private code. Direct table writes are forbidden.
do $$declare t text;begin foreach t in array array['building_members','building_settings','building_floors','building_locations','building_records','building_notifications'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);execute format('grant select on public.%I to authenticated',t);end loop;
foreach t in array array['admins','audit','operations','backups'] loop execute format('alter table building_private.%I enable row level security',t);execute format('revoke all on building_private.%I from public,anon,authenticated,service_role',t);end loop;end$$;
create policy building_members_read on public.building_members for select to authenticated using(user_id=auth.uid() or building_private.admin());
create policy building_settings_read on public.building_settings for select to authenticated using((select building_private.member()));
create policy building_floors_read on public.building_floors for select to authenticated using((select building_private.member()));
create policy building_locations_read on public.building_locations for select to authenticated using((select building_private.member()));
create policy building_records_read on public.building_records for select to authenticated using(building_private.readable(created_by,deleted_at));
create policy building_notices_read on public.building_notifications for select to authenticated using(recipient_id=auth.uid() and (select building_private.member()));
-- Private helpers are not automatically callable. Expose only deliberate signed-in RPC wrappers.
revoke all on all functions in schema building_private from public,anon,authenticated,service_role;
grant execute on function building_private.role(),building_private.member(),building_private.admin(),building_private.all_records(),building_private.followup(),building_private.can_stats(),building_private.readable(uuid,timestamptz),building_private.storage_read(text) to authenticated;

grant execute on function building_private.context() to authenticated;
create function public.building_context() returns jsonb language sql security invoker set search_path='' as $$select building_private.context()$$;
revoke all on function public.building_context() from public,anon;
grant execute on function public.building_context() to authenticated;

grant execute on function building_private.save(jsonb) to authenticated;
create function public.building_save(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select building_private.save(payload)$$;
revoke all on function public.building_save(jsonb) from public,anon;
grant execute on function public.building_save(jsonb) to authenticated;

grant execute on function building_private.follow(jsonb) to authenticated;
create function public.building_follow(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select building_private.follow(payload)$$;
revoke all on function public.building_follow(jsonb) from public,anon;
grant execute on function public.building_follow(jsonb) to authenticated;

grant execute on function building_private.remove(uuid,boolean,integer,text) to authenticated;
create function public.building_remove(record_id uuid,removed boolean,expected_version integer,reason text) returns void language sql security invoker set search_path='' as $$select building_private.remove(record_id,removed,expected_version,reason)$$;
revoke all on function public.building_remove(uuid,boolean,integer,text) from public,anon;
grant execute on function public.building_remove(uuid,boolean,integer,text) to authenticated;

grant execute on function building_private.manage_location(jsonb) to authenticated;
create function public.building_manage_location(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select building_private.manage_location(payload)$$;
revoke all on function public.building_manage_location(jsonb) from public,anon;
grant execute on function public.building_manage_location(jsonb) to authenticated;

grant execute on function building_private.manage_member(uuid,text,boolean,text) to authenticated;
create function public.building_manage_member(uid uuid,new_role text,enabled boolean,reason text) returns void language sql security invoker set search_path='' as $$select building_private.manage_member(uid,new_role,enabled,reason)$$;
revoke all on function public.building_manage_member(uuid,text,boolean,text) from public,anon;
grant execute on function public.building_manage_member(uuid,text,boolean,text) to authenticated;

grant execute on function building_private.settings(integer,boolean) to authenticated;
create function public.building_settings(days integer,notifications boolean) returns void language sql security invoker set search_path='' as $$select building_private.settings(days,notifications)$$;
revoke all on function public.building_settings(integer,boolean) from public,anon;
grant execute on function public.building_settings(integer,boolean) to authenticated;

grant execute on function building_private.staff() to authenticated;
create function public.building_staff() returns jsonb language sql security invoker set search_path='' as $$select building_private.staff()$$;
revoke all on function public.building_staff() from public,anon;
grant execute on function public.building_staff() to authenticated;

grant execute on function building_private.history(uuid) to authenticated;
create function public.building_history(record_id uuid) returns jsonb language sql security invoker set search_path='' as $$select building_private.history(record_id)$$;
revoke all on function public.building_history(uuid) from public,anon;
grant execute on function public.building_history(uuid) to authenticated;

grant execute on function building_private.mark_read(uuid) to authenticated;
create function public.building_mark_read(notice_id uuid) returns void language sql security invoker set search_path='' as $$select building_private.mark_read(notice_id)$$;
revoke all on function public.building_mark_read(uuid) from public,anon;
grant execute on function public.building_mark_read(uuid) to authenticated;
