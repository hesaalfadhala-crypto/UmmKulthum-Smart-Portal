-- Post-deployment SQL/RLS check only. All fixtures are inside a rolled-back transaction.
begin;
select set_config('qa.principal',(select id::text from public.profiles where role='principal' and school_access='all' limit 1),true);
select set_config('qa.hessa',(select id::text from public.profiles where role='assistant_principal' and school_access='all' limit 1),true);
select set_config('qa.teacher',gen_random_uuid()::text,true),set_config('qa.other',gen_random_uuid()::text,true),set_config('qa.first',gen_random_uuid()::text,true),set_config('qa.coord',gen_random_uuid()::text,true),set_config('qa.deputy',gen_random_uuid()::text,true);
insert into auth.users(id,email,aud,role)
select current_setting('qa.'||n)::uuid,'qa-visits-'||n||'-'||current_setting('qa.'||n)||'@example.invalid','authenticated','authenticated' from unnest(array['teacher','other','first','coord','deputy']) n;
insert into public.profiles(id,full_name,role,department,school_access)
values(current_setting('qa.teacher')::uuid,'QA_ONLY_ROLLBACK_TEACHER','teacher','QA_العربية','own'),(current_setting('qa.other')::uuid,'QA_ONLY_ROLLBACK_OTHER','teacher','QA_الرياضيات','own'),(current_setting('qa.first')::uuid,'QA_ONLY_ROLLBACK_FIRST','first_teacher','QA_العربية','own'),(current_setting('qa.coord')::uuid,'QA_ONLY_ROLLBACK_COORD','coordinator','QA_الإنجليزية','own'),(current_setting('qa.deputy')::uuid,'QA_ONLY_ROLLBACK_DEPUTY','assistant_principal','QA_الرياضيات','own');
select set_config('qa.t1',gen_random_uuid()::text,true),set_config('qa.t2',gen_random_uuid()::text,true),set_config('qa.t3',gen_random_uuid()::text,true),set_config('qa.t4',gen_random_uuid()::text,true),set_config('qa.request',gen_random_uuid()::text,true);
insert into public.observation_teachers(id,user_id,full_name,department,academic_year) values
(current_setting('qa.t1')::uuid,current_setting('qa.teacher')::uuid,'QA_ONLY_ROLLBACK_1','QA_العربية','2098-2099'),
(current_setting('qa.t2')::uuid,current_setting('qa.other')::uuid,'QA_ONLY_ROLLBACK_2','QA_الرياضيات','2098-2099'),
(current_setting('qa.t3')::uuid,null,'QA_ONLY_ROLLBACK_3','QA_الإنجليزية','2098-2099'),
(current_setting('qa.t4')::uuid,null,'QA_ONLY_ROLLBACK_4','QA_العربية','2098-2099');
insert into public.observation_access(user_id,department,domain_ids,can_edit) values
(current_setting('qa.first')::uuid,'QA_العربية','{}',true),
(current_setting('qa.coord')::uuid,'QA_الإنجليزية','{}',true),
(current_setting('qa.deputy')::uuid,'QA_الرياضيات','{1,2}',false);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.principal'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare t text; l int; ratings jsonb; payload jsonb; v jsonb; s jsonb; rep uuid; begin
 for t,l in select * from (values('t1',1),('t1',4),('t2',2),('t3',3)) x(t,l) loop
  select jsonb_agg(jsonb_build_object('criterion_id',n,'level',case when t='t1' and l=4 and n=3 then null when t='t2' and n=18 then null else l end) order by n) into ratings from generate_series(1,18)n;
  payload:=jsonb_build_object('teacher_id',current_setting('qa.'||t),'visit_date','2098-10-11','academic_year','2098-2099','semester',1,'visit_type','زيارة صفية','lesson_title','QA_ONLY_ROLLBACK','status','final');
  v:=public.save_classroom_visit(payload,ratings,jsonb_build_object('final_judgment',l,'judgment_basis','QA: manual judgment, no arithmetic mean'),null);
  if t='t1' and l=1 then perform set_config('qa.v1',v->>'id',true); end if;
 end loop;
 s:=public.analyze_classroom_visits('{"scope":"school","academic_year":"2098-2099"}');
 if jsonb_array_length(s->'visits')<>4 or jsonb_array_length(s->'coverage_teacher_ids')<>4 or jsonb_array_length(s->'ratings')<>72 then raise exception 'School capture incomplete'; end if;
 s:=public.analyze_classroom_visits(jsonb_build_object('scope','teacher','teacher_id',current_setting('qa.t1'),'academic_year','2098-2099'));
 if jsonb_array_length(s->'visits')<>2 then raise exception 'Teacher capture failed';end if;
 if (select count(*) from jsonb_array_elements(s->'ratings')r where (r->>'criterion_id')::int=3 and (r->>'level')::int between 1 and 4)<>1 then raise exception 'Missing ratings denominator failed';end if;
 s:=public.analyze_classroom_visits('{"scope":"department","department":"QA_العربية","academic_year":"2098-2099"}');
 if jsonb_array_length(s->'visits')<>2 or jsonb_array_length(s->'coverage_teacher_ids')<>2 then raise exception 'Department capture failed';end if;
 select jsonb_agg(jsonb_build_object('criterion_id',n,'level',null) order by n) into ratings from generate_series(1,18)n;
 payload:=jsonb_build_object('teacher_id',current_setting('qa.t4'),'visit_date','2098-10-11','academic_year','2098-2099','semester',1,'visit_type','زيارة صفية','lesson_title','QA_ONLY_ROLLBACK_DRAFT','status','draft','request_id',current_setting('qa.request'));
 v:=public.save_classroom_visit(payload,ratings,'{}',null);perform set_config('qa.draft',v->>'id',true);
 if public.save_classroom_visit(payload,ratings,'{}',null)->>'id'<>v->>'id' then raise exception 'Retry created duplicate';end if;
 rep:=public.save_classroom_report(jsonb_build_object('scope','teacher','teacher_id',current_setting('qa.t1'),'academic_year','2098-2099'),null,'unified-percent','QA_ONLY_ROLLBACK');
 perform set_config('qa.report',rep::text,true);
 if (select count(*) from public.classroom_reports where id=rep)<>1 then raise exception 'Report save/read failed';end if;
 begin update public.classroom_reports set creator_name='FORGED' where id=rep;raise exception 'Report editable';exception when insufficient_privilege then null;end;
 -- Read back a saved visit, update it, reject stale versions, preserve the report snapshot.
 if (select count(*) from public.classroom_visit_ratings where visit_id=current_setting('qa.v1')::uuid)<>18 then raise exception 'Visit reopen failed';end if;
 select jsonb_agg(jsonb_build_object('criterion_id',n,'level',2) order by n) into ratings from generate_series(1,18)n;
 payload:=jsonb_build_object('id',current_setting('qa.v1'),'teacher_id',current_setting('qa.t1'),'visit_date','2098-10-11','academic_year','2098-2099','semester',1,'visit_type','زيارة صفية','lesson_title','QA_ONLY_ROLLBACK_UPDATED','status','final');
 v:=public.save_classroom_visit(payload,ratings,'{"final_judgment":2,"judgment_basis":"QA manual basis"}',1);
 if (v->>'version')::int<>2 then raise exception 'Update version failed';end if;
 begin perform public.save_classroom_visit(payload,ratings,'{"final_judgment":2,"judgment_basis":"QA manual basis"}',1);raise exception 'Stale overwrite allowed';exception when serialization_failure then null;end;
 if not exists(select 1 from public.classroom_reports x,jsonb_array_elements(x.snapshot->'ratings') r where x.id=rep and (r->>'visit_id')::uuid=current_setting('qa.v1')::uuid and (r->>'criterion_id')::int=1 and (r->>'level')::int=1) then raise exception 'Saved report changed after visit edit';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.hessa'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if jsonb_array_length(public.analyze_classroom_visits('{"scope":"school","academic_year":"2098-2099"}')->'visits')<>4 then raise exception 'All-school assistant denied';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.teacher'),'role','authenticated','user_metadata',jsonb_build_object('role','principal','school_access','all'))::text,true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.classroom_visits)<>2 or exists(select 1 from public.classroom_visits where teacher_id<>current_setting('qa.t1')::uuid) then raise exception 'Teacher privacy failed';end if;
 if (select count(*) from public.classroom_reports where id=current_setting('qa.report')::uuid)<>1 then raise exception 'Own teacher report hidden';end if;
 begin perform public.analyze_classroom_visits('{"scope":"school","academic_year":"2098-2099"}');raise exception 'Teacher school access';exception when insufficient_privilege then null;end;
 begin update public.observation_access set can_edit=true;raise exception 'Grant elevation';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.other'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if exists(select 1 from public.classroom_reports where id=current_setting('qa.report')::uuid) then raise exception 'Other teacher report exposed';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.deputy'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.classroom_visits)<>1 or (select count(*) from public.classroom_visit_ratings)<>7 or exists(select 1 from public.classroom_visit_details) then raise exception 'Deputy domain/department leak';end if;
 begin perform public.analyze_classroom_visits('{"scope":"department","department":"QA_العربية","academic_year":"2098-2099"}');raise exception 'Deputy other department';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.first'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if jsonb_array_length(public.analyze_classroom_visits('{"scope":"department","department":"QA_العربية","academic_year":"2098-2099"}')->'visits')<>2 then raise exception 'First teacher department denied';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.coord'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if jsonb_array_length(public.analyze_classroom_visits('{"scope":"department","department":"QA_الإنجليزية","academic_year":"2098-2099"}')->'visits')<>1 then raise exception 'Coordinator department denied';end if;end $$;
reset role;
select set_config('request.jwt.claims','{}',true);
set local role anon;
do $$ begin
 begin perform count(*) from public.observation_teachers;raise exception 'Anonymous roster exposed';exception when insufficient_privilege then null;end;
 begin perform public.analyze_classroom_visits('{"scope":"school"}');raise exception 'Anonymous RPC allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: deployed PostgreSQL save/reopen/update/retry/report snapshot, real leadership scopes, synthetic teacher/department/domain isolation and anonymous access; all fixtures rolled back' as result;
