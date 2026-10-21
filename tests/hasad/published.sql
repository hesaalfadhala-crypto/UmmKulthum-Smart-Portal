-- Synthetic workflow, only inside one transaction; no persistent notifications or rewards.
begin;
select set_config('test.author',(select m.user_id::text from public.hasad_members m where category_id='digital' and active and not exists(select 1 from hasad_private.administrators a where a.user_id=m.user_id) order by user_id limit 1),true);
select set_config('test.recipient',(select p.id::text from public.profiles p where not exists(select 1 from public.hasad_members m where m.user_id=p.id and active) and not exists(select 1 from hasad_private.administrators a where a.user_id=p.id) order by id limit 1),true);
select set_config('test.recipient2',(select p.id::text from public.profiles p where not exists(select 1 from public.hasad_members m where m.user_id=p.id and active) and not exists(select 1 from hasad_private.administrators a where a.user_id=p.id) order by id offset 1 limit 1),true);
select set_config('test.peer',(select p.id::text from public.profiles p where not exists(select 1 from public.hasad_members m where m.user_id=p.id and active) and not exists(select 1 from hasad_private.administrators a where a.user_id=p.id) order by id offset 2 limit 1),true);
select set_config('test.principal',(select user_id::text from hasad_private.administrators where principal),true);
select set_config('test.assistant',(select user_id::text from hasad_private.administrators where not principal),true);
select set_config('request.jwt.claim.sub',current_setting('test.author'),true);
set local role authenticated;
do $$declare payload jsonb;a jsonb;begin
 payload:=jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'category_id','digital','level_id','digital-distinguished','title','اختبار حصاد وهمي مؤقت','event_date','2026-10-21','academic_year','2026-2027','criteria_ids',jsonb_build_array('digital-distinguished-1'),'reason','سبب وهمي خاص','public_summary','إشادة تجريبية','recipients',jsonb_build_array(current_setting('test.recipient'),current_setting('test.recipient2')),'files','[]'::jsonb);
 a:=public.hasad_save(payload);perform set_config('test.aid',a->>'id',true);
 if public.hasad_save(payload)->>'version'<>a->>'version' then raise exception 'Retry was not idempotent';end if;
 a:=public.hasad_action((a->>'id')::uuid,(a->>'version')::int,'submit');perform set_config('test.version',a->>'version',true);
 begin perform public.hasad_action((a->>'id')::uuid,(a->>'version')::int,'approve','',true);raise exception 'Committee approved';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.recipient'),true);
do $$begin
 if jsonb_array_length(public.hasad_mine())<>0 or exists(select 1 from public.hasad_notifications) then raise exception 'Premature disclosure';end if;
 begin update public.hasad_awards set status='approved';raise exception 'Direct state write allowed';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.assistant'),true);
do $$begin
 if not (public.hasad_context()->>'admin')::boolean or (public.hasad_context()->>'can_approve')::boolean then raise exception 'Assistant approval scope wrong';end if;
 begin perform public.hasad_action(current_setting('test.aid')::uuid,current_setting('test.version')::int,'approve','',true);raise exception 'Undelegated approval allowed';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.principal'),true);
do $$declare a jsonb;w uuid;begin
 a:=public.hasad_action(current_setting('test.aid')::uuid,current_setting('test.version')::int,'approve','',true,false);
 if exists(select 1 from public.hasad_public_cards where award_id=(a->>'id')::uuid) then raise exception 'Private award appeared publicly';end if;
 if (select count(*) from public.hasad_rewards where award_id=(a->>'id')::uuid)<>2 then raise exception 'Group entitlement count wrong';end if;
 select id into w from public.hasad_rewards where award_id=(a->>'id')::uuid and user_id=current_setting('test.recipient')::uuid;
 perform public.hasad_reward_update(w,'executed','2026-10-22','تنفيذ وهمي سيُلغى');
 a:=public.hasad_save(jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'category_id','department','level_id','department-distinguished','title','اختبار قسم وهمي','event_date','2026-10-21','period_from','2026-10-01','period_to','2026-10-31','academic_year','2026-2027','department','قسم تجريبي','is_department',true,'criteria_ids',jsonb_build_array('department-distinguished-1'),'reason','سبب قسم وهمي','public_summary','تميز القسم','recipients',jsonb_build_array(current_setting('test.recipient'),current_setting('test.recipient2')),'files','[]'::jsonb));
 a:=public.hasad_action((a->>'id')::uuid,(a->>'version')::int,'approve','',true,true);
 if (select count(distinct award_id) from public.hasad_public_cards where is_department)<>1 then raise exception 'Department award duplicated';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.recipient'),true);
do $$declare mine jsonb;begin
 mine:=public.hasad_mine();if jsonb_array_length(mine)<>2 then raise exception 'Personal awards missing';end if;
 if exists(select 1 from public.hasad_rewards where user_id<>auth.uid()) then raise exception 'Peer reward disclosure';end if;
 if (select count(*) from public.hasad_notifications)<>2 then raise exception 'Wrong recipient notifications';end if;
 if exists(select 1 from public.hasad_awards) then raise exception 'Private nomination row exposed';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.peer'),true);
do $$begin
 if jsonb_array_length(public.hasad_mine())<>0 or exists(select 1 from public.hasad_rewards) or exists(select 1 from public.hasad_notifications) then raise exception 'Peer disclosure';end if;
 if (select count(*) from public.hasad_public_cards)<>2 then raise exception 'Public department projection unavailable';end if;
 begin perform public.hasad_staff();raise exception 'Unauthorized chooser exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select jsonb_build_object('rolled_back_workflow','passed','real_awards',(select count(*) from public.hasad_awards),'real_notifications',(select count(*) from public.hasad_notifications),'real_rewards',(select count(*) from public.hasad_rewards),'profiles_hash',(select md5(jsonb_agg(to_jsonb(p) order by id)::text) from public.profiles p),'docs_hash',(select md5(jsonb_agg(to_jsonb(d) order by id)::text) from public.documentations d)) verification;
