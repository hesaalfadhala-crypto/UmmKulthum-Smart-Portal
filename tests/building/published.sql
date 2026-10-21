-- Live schema test using transaction-local role contexts and synthetic records only.
-- All rows and storage metadata are rolled back. No real notification is created.
begin;
create temporary table building_qa_result(result jsonb);
do $$declare a uuid;m uuid;outsider uuid;f jsonb;t jsonb;c jsonb;l jsonb;r jsonb;s jsonb;req uuid;rid uuid;path text;ctx jsonb;n integer;person record;checked integer:=0;begin
 select user_id into a from building_private.admins order by user_id limit 1;
 select user_id into m from public.building_members where role='member' and active order by user_id limit 1;
 select id into outsider from public.profiles where id not in(select user_id from public.building_members where active) order by id limit 1;
 if a is null or m is null or outsider is null then raise exception 'Need approved admin, member and nonmember accounts';end if;
 for person in select user_id,role from public.building_members where active loop
 perform set_config('request.jwt.claim.sub',person.user_id::text,true);execute 'set local role authenticated';ctx:=public.building_context();if ctx->>'role'<>person.role then raise exception 'Role mismatch';end if;checked:=checked+1;execute 'reset role';end loop;
 perform set_config('request.jwt.claim.sub',a::text,true);execute 'set local role authenticated';
 f:=public.building_manage_location(jsonb_build_object('entity','floor','name','QA-طابق مؤقت لا يحفظ'));
 t:=public.building_manage_location(jsonb_build_object('entity','location','floor_id',f->>'id','type','toilet','name','QA-دورة مياه مؤقتة'));
 c:=public.building_manage_location(jsonb_build_object('entity','location','floor_id',f->>'id','type','classroom','name','QA-فصل وهمي/1','grade','صف وهمي','section','1'));
 l:=public.building_manage_location(jsonb_build_object('entity','location','floor_id',f->>'id','type','corridor','name','QA-ممر مؤقت'));
 execute 'reset role';perform set_config('request.jwt.claim.sub',m::text,true);execute 'set local role authenticated';
 rid:=gen_random_uuid();req:=gen_random_uuid();path:=m::text||'/'||rid::text||'/'||gen_random_uuid()::text||'.jpg';
 insert into storage.objects(bucket_id,name,owner_id,metadata) values('school-building-files',path,m::text,'{"size":100,"mimetype":"image/jpeg"}');
 r:=public.building_save(jsonb_build_object('id',rid,'request_id',req,'kind','cleanliness','location_id',t->>'id','observed_at',now()-interval '1 hour','ratings',jsonb_build_array('excellent','good','poor','good'),'supervisors',jsonb_build_array('assistant','aisha','services'),'files',jsonb_build_array(jsonb_build_object('bucket','school-building-files','path',path,'name','QA-image.jpg','kind','photo')),'is_test',true));
 s:=public.building_save(jsonb_build_object('id',rid,'request_id',req,'kind','cleanliness','location_id',t->>'id','observed_at',now()-interval '1 hour','ratings',jsonb_build_array('excellent','good','poor','good'),'supervisors',jsonb_build_array('assistant','aisha','services'),'files',jsonb_build_array(jsonb_build_object('bucket','school-building-files','path',path,'name','QA-image.jpg','kind','photo')),'is_test',true));
 if r->>'id'<>s->>'id' or r->>'version'<>s->>'version' then raise exception 'Idempotency failed';end if;
 perform public.building_save(jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'kind','supplies','location_id',t->>'id','observed_at',now()-interval '1 hour','ratings',jsonb_build_array('available','missing','available','available'),'is_test',true));
 s:=public.building_save(jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'kind','toilet_maintenance','location_id',t->>'id','observed_at',now()-interval '1 hour','issue_types',jsonb_build_array('leak'),'is_test',true));
 for n in 1..2 loop perform public.building_save(jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'kind','building_maintenance','location_id',l->>'id','observed_at',now()-interval '1 hour','issue_types',jsonb_build_array('light'),'position','middle','is_test',true));end loop;
 perform public.building_save(jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'kind','building_maintenance','location_id',c->>'id','observed_at',now()-interval '1 hour','issue_types',jsonb_build_array('curtains','window','door','ac'),'is_test',true));
 if (select count(*) from public.building_records where location_id=(l->>'id')::uuid and 'light'=any(issue_types))<>2 then raise exception 'Repeated site records mismatch';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',outsider::text,true);execute 'set local role authenticated';
 if (select count(*) from public.building_records where is_test)<>0 or (select count(*) from storage.objects where bucket_id='school-building-files' and name=path)<>0 then raise exception 'RLS leaked another user record or file';end if;
 begin perform public.building_context();raise exception 'Unexpected access';exception when insufficient_privilege then null;end;
 execute 'reset role';perform set_config('request.jwt.claim.sub',a::text,true);execute 'set local role authenticated';
 s:=public.building_follow(jsonb_build_object('id',s->>'id','version',(s->>'version')::int,'request_id',gen_random_uuid(),'status','repaired','action_taken','إصلاح اختباري مؤقت','repair_date',(now() at time zone 'Asia/Bahrain')::date));
 if s->>'status'<>'repaired' or jsonb_array_length(public.building_history((s->>'id')::uuid))<2 then raise exception 'Followup/history failure';end if;
 execute 'reset role';if (select count(*) from public.building_notifications)<>0 then raise exception 'Unexpected real notifications';end if;
 insert into building_qa_result values(jsonb_build_object('approved_account_contexts_checked',checked,'forms',4,'synthetic_records',6,'same_id_retry',true,'corridor_reports',2,'classroom_link',true,'protected_file_metadata',true,'outsider_blocked',true,'repair_and_history',true,'notifications_created',0));
 end$$;
select * from building_qa_result;
rollback;
