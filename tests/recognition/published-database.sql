begin;
select set_config('request.jwt.claim.sub',(select p.id::text from public.profiles p join documentation_private.report_admins a on a.user_id=p.id where p.role='principal'),'true');
set local role authenticated;
do $$
declare typ text;s text;d jsonb;r jsonb;rid bigint;staff jsonb;teacher uuid;principal uuid:=auth.uid();hessa uuid;cnt int;total numeric;denied boolean;
begin
 select jsonb_agg(x) into staff from (select * from public.recognition_staff() limit 2)x;
 for typ in select unnest(array['فعالية','ورشة تدريبية','مبادرة','ملتقى']) loop
  foreach s in array array['internal','external'] loop
   d:=jsonb_build_object('type',typ,'projects','[]'::jsonb,'executionScope',s,'organizingEntity','جهة منظمة تجريبية QA-20261015','hostingEntity','جهة مستضيفة تجريبية QA-20261015');
   insert into public.documentations(created_by,request_id,activity,activity_type,activity_date,details) values(principal,gen_random_uuid(),'QA-20261015 — اختبار نطاق — يُلغى تلقائيًا',typ,'2026-10-15',d) returning id into rid;
   if not exists(select 1 from public.documentations where id=rid and execution_scope=s and(s='internal' and organizing_entity is null and hosting_entity is null or s='external' and organizing_entity is not null and hosting_entity is not null)) then raise exception 'Scope round trip failed';end if;
   if typ='ورشة تدريبية' and not exists(select 1 from public.documentations where id=rid and workshop_type=execution_scope and executing_agency is not distinct from organizing_entity) then raise exception 'Workshop alias failed';end if;
  end loop;
 end loop;
 denied:=false;
 begin insert into public.documentations(created_by,activity,activity_type,details)values(principal,'QA-20261015 invalid','ملتقى','{"executionScope":"external","organizingEntity":"جهة فقط"}');exception when others then denied:=true;end;
 if not denied then raise exception 'Missing host accepted';end if;
 for cnt in 1..2 loop
  r:=jsonb_build_object('title','QA-20261015 — تكريم تجريبي — يُلغى تلقائيًا','date','2026-10-15','recipientIds',case when cnt=1 then jsonb_build_array(staff->0->>'id') else jsonb_build_array(staff->0->>'id',staff->1->>'id') end,'kind','جهود استثنائية','reason','بيانات اختبار واضحة وليست تكريمًا حقيقيًا','awards',jsonb_build_array('ساعات سعادة','شهادة شكر وتقدير'),'hours',1.5,'presenter','جهة اختبار');
  d:=jsonb_build_object('projects',jsonb_build_array('أنتِ تستحقين الشكر'),'executionScope','internal','recognition',r);
  insert into public.documentations(created_by,request_id,activity_type,semester,details) values(principal,gen_random_uuid(),'فعالية','الفصل الدراسي الأول',d) returning id into rid;
  if not exists(select 1 from public.documentations where id=rid and jsonb_array_length(details->'recognition'->'recipients')=cnt) then raise exception 'Recognition account snapshot failed';end if;
  if not exists(select 1 from public.documentation_tag_memberships() m join public.school_tags t on m.tag_id=t.id where m.documentation_id=rid and t.name='أنتِ تستحقين الشكر') then raise exception 'Archive linkage failed';end if;
 end loop;
 select sum((details->'recognition'->>'hours')::numeric*jsonb_array_length(details->'recognition'->'recipients')) into total from public.documentations where activity='QA-20261015 — تكريم تجريبي — يُلغى تلقائيًا';
 if total<>4.5 then raise exception 'Hours totals failed: %',total;end if;
 select s.id into teacher from public.recognition_staff() s where s.id<>principal and s.full_name not like '%حصه%فضال%' limit 1;
 perform set_config('request.jwt.claim.sub',teacher::text,true);
 if exists(select 1 from public.documentations where activity='QA-20261015 — تكريم تجريبي — يُلغى تلقائيًا') then raise exception 'Unauthorized recognition read';end if;
 denied:=false;begin insert into public.documentations(created_by,request_id,activity_type,details)values(teacher,gen_random_uuid(),'فعالية',d);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Unauthorized recognition write';end if;
 denied:=false;begin perform public.set_report_deleted(rid,true,0);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Unauthorized deletion';end if;
 perform set_config('request.jwt.claim.sub',principal::text,true);
 perform public.set_report_deleted(rid,true,0);perform public.set_report_deleted(rid,false,1);
 if not exists(select 1 from public.documentations where id=rid and deleted_at is null and deletion_version=2) then raise exception 'Soft delete/restore failed';end if;
end$$;
rollback;
select 'PASS: 8 scope records, missing-host rejection, single/multiple recognition, 4.5 hours, archive memberships, RLS read/write/delete, logical deletion and restore; all test writes rolled back.' as verification;
