-- Deployed PostgreSQL/RLS verification. Fixtures never leave this rollback transaction.
begin;
select set_config('qa.center_before',(select count(*)::text from public.documentations),true);
select set_config('qa.center_hash',(select md5(coalesce(string_agg(to_jsonb(d)::text,'' order by id),'')) from public.documentations d),true);
select set_config('qa.center_principal',(select id::text from public.profiles where role='principal' and school_access='all' limit 1),true);
select set_config('qa.center_hessa',(select id::text from public.profiles where role='assistant_principal' and school_access='all' limit 1),true);
select set_config('qa.center_teacher',gen_random_uuid()::text,true),set_config('qa.center_other',gen_random_uuid()::text,true),set_config('qa.center_manager',gen_random_uuid()::text,true),set_config('qa.center_request',gen_random_uuid()::text,true),set_config('qa.center_doc_request',gen_random_uuid()::text,true);
insert into auth.users(id,email,aud,role) select current_setting('qa.center_'||n)::uuid,'qa-center-'||n||'-'||current_setting('qa.center_'||n)||'@example.invalid','authenticated','authenticated' from unnest(array['teacher','other','manager'])n;
insert into public.profiles(id,full_name,role,department,school_access) select current_setting('qa.center_'||n)::uuid,'QA_ONLY_ROLLBACK_CENTER_'||n,'teacher','QA_مركز_الدعم','own' from unnest(array['teacher','other','manager'])n;
insert into public.support_center_access(user_id,permission) values(current_setting('qa.center_manager')::uuid,'manage');
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_teacher'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare p jsonb;v jsonb; begin
 p:=jsonb_build_object('request_id',current_setting('qa.center_request'),'kind','booking','title','QA_ONLY_ROLLBACK_BOOKING','date','2098-10-11','from','09:00','to','10:00');v:=public.save_support_request(p);perform set_config('qa.center_booking',v->>'id',true);
 if v->>'status'<>'pending' or public.save_support_request(p)->>'id'<>v->>'id' then raise exception 'Booking pending/retry failed';end if;
 if (select count(*) from public.support_requests where id=(v->>'id')::uuid)<>1 then raise exception 'Booking reopen failed';end if;
 p:=jsonb_build_object('request_id',gen_random_uuid(),'kind','need','title','QA_ONLY_ROLLBACK_NEED');v:=public.save_support_request(p);perform set_config('qa.center_need',v->>'id',true);
 p:=jsonb_build_object('request_id',gen_random_uuid(),'kind','proposal','title','QA_ONLY_ROLLBACK_PROGRAM','date','2098-10-11','from','11:00','to','12:00','details','QA_ONLY_ROLLBACK');v:=public.save_support_request(p);perform set_config('qa.center_proposal',v->>'id',true);
 p:=jsonb_build_object('request_id',gen_random_uuid(),'kind','booking','title','QA_ONLY_ROLLBACK_CONFLICT','date','2098-10-11','from','09:30','to','10:30');v:=public.save_support_request(p);perform set_config('qa.center_conflict',v->>'id',true);
 begin update public.support_requests set status='approved' where id=current_setting('qa.center_booking')::uuid;raise exception 'Self approval allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_other'),'role','authenticated','user_metadata',jsonb_build_object('role','principal','school_access','all'))::text,true);
set local role authenticated;
do $$begin if exists(select 1 from public.support_requests where id=current_setting('qa.center_booking')::uuid) then raise exception 'Other member booking exposed';end if;
 begin perform public.review_support_request(current_setting('qa.center_booking')::uuid,'approved','FORGED',1);raise exception 'Member elevated';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_manager'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare v jsonb;begin
 if not (public.support_center_context()->>'manager')::boolean or (select count(*) from public.support_requests where department='QA_مركز_الدعم')>4 then raise exception 'Manager context invalid';end if;
 if not exists(select 1 from public.support_requests where id=current_setting('qa.center_booking')::uuid) then raise exception 'Manager queue missing';end if;
 perform public.review_support_request(current_setting('qa.center_booking')::uuid,'approved','QA_ONLY_ROLLBACK',1);
 begin perform public.review_support_request(current_setting('qa.center_conflict')::uuid,'approved','QA_ONLY_ROLLBACK',1);raise exception 'Overlap allowed';exception when exclusion_violation then null;end;
 v:=public.review_support_request(current_setting('qa.center_proposal')::uuid,'approved','QA_ONLY_ROLLBACK',1);perform set_config('qa.center_program',v->>'program_id',true);
 perform public.review_support_request(current_setting('qa.center_need')::uuid,'approved','QA_ONLY_ROLLBACK',1);
 if jsonb_array_length(public.support_busy_times('2098-10-11','2098-10-11'))<>2 then raise exception 'Busy calendar mismatch';end if;
end $$;
reset role;
select set_config('qa.center_photo1',current_setting('qa.center_teacher')||'/'||current_setting('qa.center_doc_request')||'/'||gen_random_uuid()||'.jpg',true),set_config('qa.center_photo2',current_setting('qa.center_teacher')||'/'||current_setting('qa.center_doc_request')||'/'||gen_random_uuid()||'.jpg',true);
insert into storage.objects(bucket_id,name,owner,owner_id) values('school-documentation-images',current_setting('qa.center_photo1'),current_setting('qa.center_teacher')::uuid,current_setting('qa.center_teacher')),('school-documentation-images',current_setting('qa.center_photo2'),current_setting('qa.center_teacher')::uuid,current_setting('qa.center_teacher'));
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_teacher'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.documentations(id,created_by,request_id,activity,activity_type,activity_date,details,photo_files,support_program_id,training_beneficiaries)
values(-92290001,current_setting('qa.center_teacher')::uuid,current_setting('qa.center_doc_request')::uuid,'QA_ONLY_ROLLBACK_WORKSHOP','ورشة تدريبية','2098-10-11','{}',jsonb_build_array(jsonb_build_object('bucket','school-documentation-images','path',current_setting('qa.center_photo1'),'width',1200,'height',800),jsonb_build_object('bucket','school-documentation-images','path',current_setting('qa.center_photo2'),'width',800,'height',1200)),current_setting('qa.center_program')::uuid,15);
do $$declare v jsonb;begin
 v:=public.save_support_impact(jsonb_build_object('request_id',gen_random_uuid(),'documentation_id',-92290001,'applied_on',(now() at time zone 'Asia/Bahrain')::date,'application','QA_ONLY_ROLLBACK_IMPACT','before_level',2,'after_level',4));perform set_config('qa.center_impact',v->>'id',true);
 if not exists(select 1 from public.support_programs where id=current_setting('qa.center_program')::uuid) then raise exception 'Member cannot read approved program';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_manager'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if (select jsonb_array_length(photo_files) from public.documentations where id=-92290001)<>2 then raise exception 'Workshop report images lost';end if;
 if (select count(*) from storage.objects where name in(current_setting('qa.center_photo1'),current_setting('qa.center_photo2')))<>2 then raise exception 'Coordinator image access failed';end if;
 if not exists(select 1 from public.support_impacts where id=current_setting('qa.center_impact')::uuid) then raise exception 'Coordinator impact missing';end if;
 if (public.support_center_summary()->>'beneficiaries')::int<15 then raise exception 'Actual workshop statistics failed';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_other'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.documentations where id=-92290001) or exists(select 1 from public.support_impacts where id=current_setting('qa.center_impact')::uuid) or exists(select 1 from storage.objects where name in(current_setting('qa.center_photo1'),current_setting('qa.center_photo2'))) then raise exception 'Other member workshop/impact/images exposed';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_principal'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if not (public.support_center_context()->>'manager')::boolean then raise exception 'Principal center denied';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.center_hessa'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if not (public.support_center_context()->>'manager')::boolean then raise exception 'All-school assistant center denied';end if;end $$;
reset role;
select set_config('request.jwt.claims','{}',true);set local role anon;
do $$begin
 begin perform public.support_center_context();raise exception 'Anonymous center allowed';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.support_requests;raise exception 'Anonymous bookings exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin if (select md5(coalesce(string_agg(to_jsonb(d)::text,'' order by id),'')) from public.documentations d where id<>-92290001)<>current_setting('qa.center_hash') then raise exception 'Original documentation changed';end if;end $$;
rollback;
select 'PASS: deployed booking/needs/proposal approval, conflict prevention, original workshop/images, impact, actual statistics, leadership/member privacy; all fixtures rolled back' as result;
