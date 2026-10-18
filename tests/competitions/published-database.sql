-- Rollback-only live-policy test: real teacher identity, entirely fictional participants.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where role='teacher' order by id limit 1),true);
select set_config('competition.qa_owner',auth.uid()::text,true),set_config('competition.qa_request',gen_random_uuid()::text,true);
set local role authenticated;
insert into public.competitions(competition_name,competition_type,department,competition_date,supervisor,created_by,request_id,students,attachments) values('اختبار تراجعي وهمي — لا يُحفظ','داخلية','قسم اختبار','2026-10-18','مشرفة وهمية',auth.uid(),current_setting('competition.qa_request')::uuid,(select jsonb_agg(jsonb_build_object('name','طالبة وهمية '||n,'class','الأول الإعدادي','section','1','place','')) from generate_series(1,7)n),'[]');
select set_config('competition.qa_id',(select id::text from competitions where request_id=current_setting('competition.qa_request')::uuid),true);
update competitions set students=students||jsonb_build_array(jsonb_build_object('name','الثامنة الوهمية','class','الثاني الإعدادي','section','2','place','')),version=version+1 where id=current_setting('competition.qa_id')::bigint;
do $$begin
 if (select student_count<>8 or version<>2 from competitions where id=current_setting('competition.qa_id')::bigint) then raise exception 'Incorrect count/version';end if;
 if (select count(*) from competitions where request_id=current_setting('competition.qa_request')::uuid)<>1 then raise exception 'Duplicate competition';end if;
 begin perform public.delete_competition(current_setting('competition.qa_id')::bigint);raise exception 'Teacher deleted report';exception when raise_exception then if sqlerrm='Teacher deleted report' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from profiles where role='teacher' and id::text<>current_setting('competition.qa_owner') order by id limit 1),true);
set local role authenticated;
do $$begin if exists(select 1 from competitions where id=current_setting('competition.qa_id')::bigint) then raise exception 'Other teacher read private roster';end if;end $$;
reset role;
select 'PASS: actual Supabase teacher RLS, 7→8 on same ID, other teacher denied, teacher deletion denied; all rolled back' as result;
rollback;
