-- Real Supabase policies and functions; everything is rolled back.
begin;
select set_config('agenda.qa_teacher',(select id::text from profiles where role='teacher' and school_access='own' order by id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('agenda.qa_teacher'),true);
set local role authenticated;
do $$declare k text;r jsonb;p jsonb;ids jsonb:='[]';begin
 if not (agenda_context()->>'member')::boolean or (agenda_context()->>'can_approve')::boolean then raise exception 'Invalid teacher scope';end if;
 foreach k in array array['school_head','supervision','parents','event','workshop','honor','other'] loop
 p:=jsonb_build_object('request_id',gen_random_uuid(),'title','اختبار أجندة وهمي — '||k,'kind',k,'kind_other',case when k='other' then 'نوع تجريبي' else '' end,'event_date','2026-10-18','slot',case when k='workshop' then 'break' when k='school_head' then 'other' else 'assembly' end,'starts_at','09:00','ends_at','10:00','department','قسم اختبار','responsible_ids',jsonb_build_array(auth.uid()),'location','موقع اختبار','audience','فئة وهمية','description','اختبار دون بيانات حقيقية','student_visible',k in('event','workshop','honor'),'repeat_until',null);
 r:=save_agenda_event(p);if save_agenda_event(p)<>r then raise exception 'Retry duplicated event';end if;ids:=ids||(r->'ids');
 end loop;
 perform set_config('agenda.qa_ids',ids::text,true);
 if (select count(*) from agenda_events where id in(select value::uuid from jsonb_array_elements_text(ids)))<>7 then raise exception 'Seven types not saved';end if;
 perform save_agenda_event(p||jsonb_build_object('request_id',gen_random_uuid(),'id',ids->>6,'version',1,'title','اسم تجريبي معدل'));
 begin perform review_agenda_event((ids->>0)::uuid,'approve','',1,gen_random_uuid());raise exception 'Teacher approved event';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from profiles where role='principal' limit 1),true);
set local role authenticated;
do $$declare ids jsonb:=current_setting('agenda.qa_ids')::jsonb;req uuid:=gen_random_uuid();begin
 if not (agenda_context()->>'can_approve')::boolean then raise exception 'Principal not authorized';end if;
 perform review_agenda_event((ids->>0)::uuid,'approve','',1,req);perform review_agenda_event((ids->>0)::uuid,'approve','',1,req);
 perform review_agenda_event((ids->>1)::uuid,'return','ملاحظة تجريبية للمراجعة',1,gen_random_uuid());
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from profiles where role='teacher' and school_access='own' and id::text<>current_setting('agenda.qa_teacher') order by id limit 1),true);
set local role authenticated;
do $$declare ids jsonb:=current_setting('agenda.qa_ids')::jsonb;begin
 if (select count(*) from agenda_events where id in(select value::uuid from jsonb_array_elements_text(ids)))<>1 then raise exception 'Unapproved peer data exposed';end if;
 begin perform save_agenda_event(jsonb_build_object('id',ids->>0,'version',2,'request_id',gen_random_uuid(),'title','ممنوع','kind','event','event_date','2026-10-18','slot','assembly','department','اختبار','responsible_ids',jsonb_build_array(auth.uid()),'location','اختبار','audience','اختبار','description','اختبار'));raise exception 'Peer edit succeeded';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('agenda.qa_teacher'),true);
set local role authenticated;
insert into documentations(created_by,request_id,activity,activity_type,activity_date,agenda_event_id,details) values(auth.uid(),gen_random_uuid(),'توثيق أجندة وهمي','فعالية','2026-10-18',(current_setting('agenda.qa_ids')::jsonb->>0)::uuid,'{"type":"فعالية","executionScope":"internal","projects":[]}');
do $$declare eid uuid:=(current_setting('agenda.qa_ids')::jsonb->>0)::uuid;begin
 if (select report_id from agenda_events where id=eid) is null then raise exception 'Report link missing';end if;
 begin insert into documentations(created_by,request_id,activity,activity_type,agenda_event_id,details) values(auth.uid(),gen_random_uuid(),'مكرر','نشاط',eid,'{}');raise exception 'Duplicate report inserted';exception when raise_exception then if sqlerrm='Duplicate report inserted' then raise;end if;end;
end $$;
reset role;
select 'PASS: seven types, idempotency, teacher edit, principal approve/return, peer privacy, original report link and duplicate prevention; all rolled back' as result;
rollback;
