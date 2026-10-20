-- Canonical competition rows. Historical documentations remain immutable aliases, never deleted.
create table competition_private.unification_backups(run_id uuid not null,source text not null,source_id text not null,snapshot jsonb not null,backed_up_at timestamptz not null default now(),primary key(run_id,source,source_id));
alter table competition_private.unification_backups enable row level security;
revoke all on competition_private.unification_backups from public,anon,authenticated;
do $$declare run uuid:=gen_random_uuid();begin
 insert into competition_private.unification_backups select run,'competition',id::text,to_jsonb(c),now() from public.competitions c;
 insert into competition_private.unification_backups select run,'documentation',id::text,to_jsonb(d),now() from public.documentations d where activity_type in('مسابقة وإنجاز طلابي','مسابقة','إنجاز');
 insert into competition_private.unification_backups select run,'storage',o.id::text,to_jsonb(o),now() from storage.objects o where exists(select 1 from public.documentations d where d.activity_type in('مسابقة وإنجاز طلابي','مسابقة','إنجاز') and (d.photo_files @> jsonb_build_array(jsonb_build_object('bucket',o.bucket_id,'path',o.name)) or d.attachment_files @> jsonb_build_array(jsonb_build_object('bucket',o.bucket_id,'path',o.name)))) or exists(select 1 from public.competitions c where c.attachments @> jsonb_build_array(jsonb_build_object('bucket',o.bucket_id,'path',o.name)));
end$$;
alter table public.competitions add column entry_kind text not null default 'competition' check(entry_kind in('competition','achievement'));
alter table public.competitions add column legacy_documentation_id bigint unique references public.documentations(id);
grant update(entry_kind) on public.competitions to authenticated;
-- Existing row authorization remains authoritative for migrated records too.
create policy competition_legacy_read on public.competitions for select to authenticated using(legacy_documentation_id is not null and exists(select 1 from public.documentations d where d.id=legacy_documentation_id and d.deleted_at is null));
create policy competition_legacy_edit on public.competitions for update to authenticated using(coalesce((public.report_edit_context(legacy_documentation_id)->>'can_edit')::boolean,false)) with check(coalesce((public.report_edit_context(legacy_documentation_id)->>'can_edit')::boolean,false));
create function public.competition_document_link(document_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$select jsonb_build_object('id',id) from public.competitions where legacy_documentation_id=document_id$$;
revoke all on function public.competition_document_link(bigint) from public,anon;grant execute on function public.competition_document_link(bigint) to authenticated;
create or replace function competition_private.guard_record() returns trigger language plpgsql security definer set search_path='' as $$
declare s jsonb; f jsonb; seen text[]:='{}'; k text; n int:=0; photos int:=0; pdfs int:=0;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Authentication required'; end if;
 if tg_op='INSERT' then
  if new.created_by is distinct from auth.uid() or new.deleted_at is not null then raise exception 'Invalid owner'; end if;
  new.version:=1; new.created_at:=now();
 else
  if new.legacy_documentation_id is distinct from old.legacy_documentation_id and not (old.legacy_documentation_id is null and exists(select 1 from public.documentations d where d.id=new.legacy_documentation_id and d.created_by=new.created_by and d.request_id=new.request_id)) then raise exception 'Protected source link';end if;
  if new.id<>old.id or new.created_by is distinct from old.created_by or new.request_id is distinct from old.request_id or new.created_at is distinct from old.created_at or (new.deleted_at is distinct from old.deleted_at and not documentation_private.can_manage()) then raise exception 'Protected competition fields'; end if;
  if new.version<>old.version+1 then raise exception 'Competition changed. Reload before saving'; end if;
  insert into competition_private.revisions(competition_id,changed_by,previous) values(old.id,auth.uid(),to_jsonb(old));
 end if;
 if new.legacy_documentation_id is not null and not exists(select 1 from public.documentations d where d.id=new.legacy_documentation_id and d.created_by=new.created_by and d.activity_type in('مسابقة وإنجاز طلابي','مسابقة','إنجاز')) then raise exception 'Invalid source documentation';end if;
 if new.entry_kind not in('competition','achievement') then raise exception 'Invalid entry kind';end if;
 if jsonb_typeof(new.details) is distinct from 'object' or octet_length(new.details::text)>2097152 then raise exception 'Invalid report details';end if;
 if tg_op='UPDATE' and auth.uid()<>new.created_by and not documentation_private.can_manage() and (new.department is distinct from old.department or new.details->'projects' is distinct from old.details->'projects') then raise exception 'Delegated scope cannot be changed';end if;
 new.supervisor:=coalesce(nullif(btrim(new.supervisor),''),(select full_name from public.profiles where id=new.created_by),'');
 if length(trim(coalesce(new.competition_name,''))) not between 1 and 300 or coalesce(new.competition_type,'') not in ('داخلية','خارجية') or coalesce(trim(new.department),'')='' or coalesce(trim(new.supervisor),'')='' then raise exception 'Incomplete competition'; end if;
 if jsonb_typeof(new.students) is distinct from 'array' or jsonb_array_length(new.students)>10000 then raise exception 'Invalid student list'; end if;
 for s in select value from jsonb_array_elements(new.students) loop
  if jsonb_typeof(s)<>'object' or length(trim(coalesce(s->>'name',''))) not between 1 and 200 or length(trim(coalesce(s->>'class',''))) not between 1 and 120 or length(coalesce(s->>'section',''))>60 or length(coalesce(s->>'place',''))>200 then raise exception 'Invalid student row'; end if;
  k:=lower(regexp_replace(translate(coalesce(s->>'name','')||'|'||coalesce(s->>'class','')||'|'||coalesce(s->>'section',''),'أإآٱ٠١٢٣٤٥٦٧٨٩','اااا0123456789'),'[[:space:]ـًٌٍَُِّْٰ]+','','g'));
  if k=any(seen) then raise exception 'Duplicate student'; end if;seen:=array_append(seen,k); n:=n+1;
 end loop;
 new.student_count:=n;
 if jsonb_typeof(new.attachments) is distinct from 'array' or jsonb_array_length(new.attachments)>15 then raise exception 'Invalid attachments'; end if;
 for f in select value from jsonb_array_elements(new.attachments) loop
  if f->>'bucket' not in('school-competition-files','school-documentation-images','school-report-files') or coalesce(f->>'path','')='' or length(coalesce(f->>'name',''))>240 or coalesce(f->>'kind','') not in ('photo','pdf') then raise exception 'Invalid file reference'; end if;
  if f->>'kind'='photo' then photos:=photos+1;else pdfs:=pdfs+1;end if;
  if f->>'bucket'<>'school-competition-files' and not exists(select 1 from public.documentations d where d.id=new.legacy_documentation_id and (case when f->>'kind'='photo' then d.photo_files else d.attachment_files end) @> jsonb_build_array(jsonb_build_object('bucket',f->>'bucket','path',f->>'path'))) then raise exception 'Legacy evidence not linked to original report';end if;
  if f->>'bucket'='school-competition-files' and not (tg_op='UPDATE' and coalesce(old.attachments,'[]') @> jsonb_build_array(f)) then
   if split_part(f->>'path','/',1)<>auth.uid()::text or f->>'path' !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|pdf)$' or not exists(select 1 from storage.objects o where o.bucket_id='school-competition-files' and o.name=f->>'path') then raise exception 'File not uploaded or not owned'; end if;
  end if;
 end loop;
 if photos>10 or pdfs>5 then raise exception 'At most 10 images and 5 PDFs'; end if;
 new.updated_at:=now();return new;
end $$;

create function public.competition_can_edit(record_id bigint) returns boolean language sql stable security invoker set search_path='' as $$select exists(select 1 from public.competitions c where c.id=record_id and c.deleted_at is null and (c.created_by=auth.uid() or documentation_private.can_manage() or coalesce((public.report_edit_context(c.legacy_documentation_id)->>'can_edit')::boolean,false)))$$;
create function public.competition_editable_ids() returns setof bigint language sql stable security invoker set search_path='' as $$select id from public.competitions where public.competition_can_edit(id)$$;
revoke all on function public.competition_can_edit(bigint),public.competition_editable_ids() from public,anon;grant execute on function public.competition_can_edit(bigint),public.competition_editable_ids() to authenticated;
-- One import per source ID. Never infer structured pupil identities from free text.
create function competition_private.import_documentation(source_id bigint) returns bigint language plpgsql security definer set search_path='' as $$
declare d public.documentations;cid bigint;extra jsonb;files jsonb;begin
 select id into cid from public.competitions where legacy_documentation_id=source_id;
 if cid is not null then return cid;end if;
 select * into d from public.documentations where id=source_id;
 if d.id is null or d.activity_type not in('مسابقة وإنجاز طلابي','مسابقة','إنجاز') or d.created_by is distinct from auth.uid() then raise exception 'Invalid legacy import owner';end if;
 select id into cid from public.competitions where created_by=d.created_by and request_id=d.request_id and legacy_documentation_id is null;
 if cid is not null then update public.competitions set legacy_documentation_id=d.id,version=version+1 where id=cid;return cid;end if;
 extra:=coalesce(d.details,'{}')||jsonb_build_object('legacyStudentsText',coalesce(nullif(d.details->>'docCompetitionStudents',''),d.competition_students,''),'legacyResultsText',coalesce(nullif(d.details->>'docCompetitionDetails',''),d.competition_details,''),'legacyRosterNeedsReview',true,'rosterReviewed',false,'sourceCreatedAt',d.created_at,'saveRequest',d.request_id);
 insert into public.competitions(legacy_documentation_id,entry_kind,created_by,request_id,competition_name,competition_type,department,competition_date,organizer,host,competition_level,supervisor,students,result,award_details,notes,status,attachments,details)
 values(d.id,case when d.activity_type='إنجاز' then 'achievement' else 'competition' end,d.created_by,coalesce(d.request_id,gen_random_uuid()),coalesce(nullif(d.activity,''),nullif(d.details->>'docCompetitionName',''),'مسابقة سابقة'),case when coalesce(d.competition_type,d.details->>'docCompetitionType')='خارجية' then 'خارجية' else 'داخلية' end,coalesce(nullif(d.department,''),'الإدارة المدرسية'),d.activity_date,coalesce(d.competition_organizer,d.details->>'docCompetitionOrganizer'),coalesce(d.competition_host,d.details->>'docCompetitionHost'),coalesce(d.competition_level,d.details->>'docCompetitionLevel'),d.executor,'[]',coalesce(d.competition_result,d.details->>'docCompetitionResult'),coalesce(d.competition_details,d.details->>'docCompetitionDetails'),'','saved','[]',extra) returning id into cid;
 select coalesce(jsonb_agg(f||jsonb_build_object('kind','photo','category','general')),'[]') into files from jsonb_array_elements(coalesce(d.photo_files,'[]')) f;
 select files||coalesce(jsonb_agg(f||jsonb_build_object('kind','pdf','category','general')),'[]') into files from jsonb_array_elements(coalesce(d.attachment_files,'[]')) f;
 update public.competitions set attachments=files,version=2 where id=cid;
 if d.deleted_at is not null then insert into competition_private.removed(competition_id,removed_by) values(cid,d.created_by);end if;
 return cid;
end$$;
revoke all on function competition_private.import_documentation(bigint) from public,anon,authenticated;
-- Backup is already complete above; copying links does not change any historical document.
do $$declare d record;previous text:=current_setting('request.jwt.claim.sub',true);begin
 for d in select id,created_by from public.documentations where activity_type in('مسابقة وإنجاز طلابي','مسابقة','إنجاز') loop
  perform set_config('request.jwt.claim.sub',d.created_by::text,true);perform competition_private.import_documentation(d.id);
 end loop;
 perform set_config('request.jwt.claim.sub',coalesce(previous,''),true);
end$$;
create function competition_private.route_legacy_insert() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.activity_type in('مسابقة وإنجاز طلابي','مسابقة','إنجاز') then
  insert into competition_private.unification_backups values(gen_random_uuid(),'documentation',new.id::text,to_jsonb(new),now());
  perform competition_private.import_documentation(new.id);
 end if;return new;
end$$;
revoke all on function competition_private.route_legacy_insert() from public,anon,authenticated;
create trigger competition_route_legacy after insert on public.documentations for each row execute function competition_private.route_legacy_insert();
create function competition_private.freeze_legacy_alias() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.competitions c where c.legacy_documentation_id=old.id) then raise exception 'هذا السجل مرتبط بمنظومة المسابقات والإنجازات. افتحي التقرير الموحد لتعديله.';end if;return new;
end$$;
revoke all on function competition_private.freeze_legacy_alias() from public,anon,authenticated;
create trigger competition_immutable_alias before update of details,activity,activity_type,photo_files,attachment_files on public.documentations for each row execute function competition_private.freeze_legacy_alias();
create or replace function competition_private.delete_record(record_id bigint) returns void language plpgsql security definer set search_path='' as $$declare c public.competitions;v integer;begin
 if not documentation_private.can_manage() then raise exception 'Only report administrators can delete' using errcode='42501';end if;
 select * into c from public.competitions where id=record_id for update;if c.id is null then raise exception 'Record not found';end if;
 if c.deleted_at is null then update public.competitions set deleted_at=now(),version=version+1 where id=c.id;end if;
 insert into competition_private.removed(competition_id,removed_by) values(c.id,auth.uid()) on conflict do nothing;
 if c.legacy_documentation_id is not null then
  select deletion_version into v from public.documentations where id=c.legacy_documentation_id;
  perform public.set_report_deleted(c.legacy_documentation_id,true,coalesce(v,0));
 end if;
end$$;
-- Only existing authorized row readers receive Realtime changes; polling remains a fallback.
do $$begin if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='competitions') then alter publication supabase_realtime add table public.competitions;end if;end$$;
-- Preserve the existing archive restore workflow for linked historical IDs.
create function competition_private.admin_document_link(document_id bigint) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('id',c.id,'removed',competition_private.is_removed(c.id)) from public.competitions c where documentation_private.can_manage() and c.legacy_documentation_id=document_id$$;
revoke all on function competition_private.admin_document_link(bigint) from public,anon;grant execute on function competition_private.admin_document_link(bigint) to authenticated;
create or replace function public.competition_document_link(document_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$select coalesce((select jsonb_build_object('id',id,'removed',false) from public.competitions where legacy_documentation_id=document_id),competition_private.admin_document_link(document_id))$$;
create function competition_private.restore_record(record_id bigint) returns void language plpgsql security definer set search_path='' as $$declare c public.competitions;v integer;begin
 if not documentation_private.can_manage() then raise exception 'Only report administrators can restore' using errcode='42501';end if;
 select * into c from public.competitions where id=record_id for update;if c.id is null then raise exception 'Record not found';end if;
 delete from competition_private.removed where competition_id=c.id;
 if c.deleted_at is not null then update public.competitions set deleted_at=null,version=version+1 where id=c.id;end if;
 if c.legacy_documentation_id is not null then select deletion_version into v from public.documentations where id=c.legacy_documentation_id;perform public.set_report_deleted(c.legacy_documentation_id,false,coalesce(v,0));end if;
end$$;
revoke all on function competition_private.restore_record(bigint) from public,anon;grant execute on function competition_private.restore_record(bigint) to authenticated;
create function public.restore_competition(record_id bigint) returns void language sql security invoker set search_path='' as $$select competition_private.restore_record(record_id)$$;
revoke all on function public.restore_competition(bigint) from public,anon;grant execute on function public.restore_competition(bigint) to authenticated;
