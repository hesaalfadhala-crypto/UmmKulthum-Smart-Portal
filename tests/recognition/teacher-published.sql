-- Live RLS assertions only. Synthetic report/media metadata; no real file blobs or records remain.
begin;
select set_config('request.jwt.claim.sub',(select id::text from profiles where role='teacher' and school_access='own' order by id limit 1),true);
select set_config('recognition.qa_owner',auth.uid()::text,true),set_config('recognition.qa_request',gen_random_uuid()::text,true),set_config('recognition.qa_photo',gen_random_uuid()::text,true);
set local role authenticated;
do $$declare c jsonb;begin select recognition_context() into c;if not (c->>'can_write')::boolean or not(c->>'can_read')::boolean or (c->>'can_read_all')::boolean then raise exception 'Incorrect teacher scope';end if;end $$;
insert into storage.objects(bucket_id,name,owner_id,metadata) values('school-documentation-images',auth.uid()::text||'/'||current_setting('recognition.qa_request')||'/'||current_setting('recognition.qa_photo')||'.jpg',auth.uid()::text,'{"size":100,"mimetype":"image/jpeg"}');
insert into documentations(created_by,request_id,activity_type,projects,details,photo_files)
values(auth.uid(),current_setting('recognition.qa_request')::uuid,'فعالية','أنتِ تستحقين الشكر',jsonb_build_object('type','فعالية','executionScope','internal','projects',jsonb_build_array('أنتِ تستحقين الشكر'),'recognition',jsonb_build_object('title','اختبار تراجعي — تكريم وهمي','date','2026-10-18','recipientIds',jsonb_build_array(auth.uid()),'kind','جهود استثنائية','reason','سبب وهمي للاختبار فقط','awards',jsonb_build_array('شهادة شكر وتقدير'),'presenter','جهة اختبار وهمية')),jsonb_build_array(jsonb_build_object('bucket','school-documentation-images','path',auth.uid()::text||'/'||current_setting('recognition.qa_request')||'/'||current_setting('recognition.qa_photo')||'.jpg','name','صورة تجريبية.jpg')));
select set_config('recognition.qa_id',(select id::text from documentations where request_id=current_setting('recognition.qa_request')::uuid),true),set_config('recognition.qa_edit',gen_random_uuid()::text,true),set_config('recognition.qa_second',gen_random_uuid()::text,true);
insert into storage.objects(bucket_id,name,owner_id,metadata) values('school-documentation-images',auth.uid()::text||'/'||current_setting('recognition.qa_edit')||'/'||current_setting('recognition.qa_second')||'.jpg',auth.uid()::text,'{"size":100,"mimetype":"image/jpeg"}');
update documentations set details=jsonb_set(details,'{recognition,reason}','"سبب تجريبي بعد التعديل"'),photo_files=photo_files||jsonb_build_array(jsonb_build_object('bucket','school-documentation-images','path',auth.uid()::text||'/'||current_setting('recognition.qa_edit')||'/'||current_setting('recognition.qa_second')||'.jpg','name','صورة ثانية تجريبية.jpg')),last_edit_request=current_setting('recognition.qa_edit')::uuid where id=current_setting('recognition.qa_id')::bigint and edit_version=0;
do $$begin
 if not exists(select 1 from documentations where id=current_setting('recognition.qa_id')::bigint and edit_version=1 and jsonb_array_length(photo_files)=2) then raise exception 'Save/edit failed';end if;
 if not exists(select 1 from documentation_tag_memberships() where documentation_id=current_setting('recognition.qa_id')::bigint) then raise exception 'Archive link missing';end if;
 begin perform set_report_deleted(current_setting('recognition.qa_id')::bigint,true,0);raise exception 'Teacher deleted';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from profiles where role='teacher' and school_access='own' and id::text<>current_setting('recognition.qa_owner') order by id limit 1),true);
set local role authenticated;
do $$begin
 if exists(select 1 from documentations where id=current_setting('recognition.qa_id')::bigint) then raise exception 'Peer report exposed';end if;
 if exists(select 1 from storage.objects where bucket_id='school-documentation-images' and name like current_setting('recognition.qa_owner')||'/'||current_setting('recognition.qa_request')||'/%') then raise exception 'Peer media exposed';end if;
 update documentations set activity='غير مسموح',last_edit_request=gen_random_uuid() where id=current_setting('recognition.qa_id')::bigint;
 if found then raise exception 'Peer edit succeeded';end if;
end $$;
reset role;
select 'PASS: real Supabase teacher RLS: create, archive link, two photos, same-ID edit; peer access/edit and teacher deletion denied. All rolled back.' as result;
rollback;
