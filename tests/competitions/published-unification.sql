-- Production-safe transactional verification: synthetic rows and metadata only, always rolled back.
begin;
select set_config('test.teacher',(select id::text from public.profiles p where role='teacher' and school_access='own' and not exists(select 1 from documentation_private.report_scope_delegates s where s.user_id=p.id) order by id limit 1),true);
select set_config('test.peer',(select id::text from public.profiles p where role='teacher' and school_access='own' and not exists(select 1 from documentation_private.report_scope_delegates s where s.user_id=p.id) order by id offset 1 limit 1),true);
select set_config('test.admin',(select user_id::text from documentation_private.report_admins limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('test.teacher'),true);
set local role authenticated;
do $$declare c public.competitions;d bigint; p text:=auth.uid()::text||'/'||gen_random_uuid()||'/'||gen_random_uuid()||'.jpg';begin
 insert into storage.objects(bucket_id,name,owner_id,metadata) values('school-competition-files',p,auth.uid()::text,'{"mimetype":"image/jpeg","size":100}');
 insert into public.competitions(created_by,request_id,entry_kind,competition_name,competition_type,department,competition_date,students,attachments,details,status)
 values(auth.uid(),gen_random_uuid(),'competition','اختبار توحيد وهمي مؤقت','داخلية','الرياضيات','2026-10-21','[{"name":"طالبة وهمية ألف","class":"السادس","section":"1","place":"المركز الأول"},{"name":"طالبة وهمية باء","class":"السادس","section":"1","place":"المركز الثاني"}]',jsonb_build_array(jsonb_build_object('bucket','school-competition-files','path',p,'name','صورة وهمية.jpg','kind','photo')),'{"saveRequest":"اختبار مؤقت"}','saved') returning * into c;
 perform set_config('test.cid',c.id::text,true);
 if c.student_count<>2 or not public.competition_can_edit(c.id) then raise exception 'Native creation failed';end if;
 update public.competitions set notes='تعديل وهمي',version=version+1 where id=c.id;
 if not exists(select 1 from storage.objects where name=p) then raise exception 'Owner evidence read failed';end if;
 insert into public.documentations(created_by,request_id,activity,activity_type,department,details)
 values(auth.uid(),c.request_id,'اختبار توحيد وهمي مؤقت','مسابقة وإنجاز طلابي','الرياضيات','{"projects":[],"docCompetitionType":"داخلية"}') returning id into d;
 if (public.competition_document_link(d)->>'id')::bigint<>c.id then raise exception 'Operation duplicated instead of linked';end if;
 if (select student_count from public.competitions where id=c.id)<>2 then raise exception 'Roster overwritten';end if;
 begin perform public.delete_competition(c.id);raise exception 'Teacher deletion permitted';exception when insufficient_privilege then null;end;
 begin update public.documentations set activity='ممنوع' where id=d;raise exception 'Mutable duplicate permitted';exception when raise_exception then if sqlerrm not like '%مرتبط%' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.peer'),true);
do $$declare n int;begin
 if exists(select 1 from public.competitions where id=current_setting('test.cid')::bigint) or public.competition_can_edit(current_setting('test.cid')::bigint) then raise exception 'Peer read leaked';end if;
 update public.competitions set notes='ممنوع',version=version+1 where id=current_setting('test.cid')::bigint;get diagnostics n=row_count;if n<>0 then raise exception 'Peer update leaked';end if;
 if exists(select 1 from storage.objects where bucket_id='school-competition-files' and name like current_setting('test.teacher')||'/%') then raise exception 'Peer evidence leaked';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.admin'),true);
do $$begin
 if not public.competition_can_edit(current_setting('test.cid')::bigint) then raise exception 'Admin authorization failed';end if;
 perform public.delete_competition(current_setting('test.cid')::bigint);
 if exists(select 1 from public.competitions where id=current_setting('test.cid')::bigint) then raise exception 'Deletion visibility failed';end if;
 perform public.restore_competition(current_setting('test.cid')::bigint);
 if not exists(select 1 from public.competitions where id=current_setting('test.cid')::bigint and student_count=2) then raise exception 'Restore failed';end if;
end$$;
reset role;
rollback;
select jsonb_build_object('transactional_tests','passed; all synthetic rows rolled back','canonical_count',(select count(*) from public.competitions),'original_rows_unchanged',(select bool_and(b.snapshot=to_jsonb(d)) from competition_private.unification_backups b join public.documentations d on b.source='documentation' and b.source_id=d.id::text)) verification;
