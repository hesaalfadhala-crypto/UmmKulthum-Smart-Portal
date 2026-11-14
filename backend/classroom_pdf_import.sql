-- Reviewed PDF import. Original observer attribution is separate from the importing user.
begin;
create or replace function observation_private.can_import_visits() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p where p.id=auth.uid()
 and p.role in ('principal','assistant_principal','first_teacher','coordinator'))
 and exists(select 1 from public.observation_teachers t where observation_private.teacher_access(t.id,true,0))
$$;
revoke all on function observation_private.can_import_visits() from public,anon;
grant execute on function observation_private.can_import_visits() to authenticated;

create table public.classroom_import_batches(
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id),
 file_name text not null check(length(file_name) between 1 and 240),
 storage_path text not null unique check(storage_path=user_id::text||'/'||id::text||'.pdf'),
 source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
 page_count integer not null check(page_count between 1 and 100),
 processed_pages integer[] not null default '{}',
 proposals jsonb not null default '[]' check(jsonb_typeof(proposals)='array' and pg_column_size(proposals)<2000000),
 extraction_calls integer not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index classroom_import_batches_owner on public.classroom_import_batches(user_id,created_at desc);
alter table public.classroom_import_batches enable row level security;
create policy import_batches_read on public.classroom_import_batches for select to authenticated using(user_id=(select auth.uid()) and observation_private.can_import_visits());
create policy import_batches_insert on public.classroom_import_batches for insert to authenticated with check(user_id=(select auth.uid()) and extraction_calls=0 and observation_private.can_import_visits());
create policy import_batches_update on public.classroom_import_batches for update to authenticated using(user_id=(select auth.uid()) and observation_private.can_import_visits()) with check(user_id=(select auth.uid()) and observation_private.can_import_visits());
revoke all on public.classroom_import_batches from public,anon,authenticated;
grant select on public.classroom_import_batches to authenticated;
grant insert(id,user_id,file_name,storage_path,source_hash,page_count) on public.classroom_import_batches to authenticated;
grant update(proposals,processed_pages,updated_at) on public.classroom_import_batches to authenticated;

create table public.classroom_import_records(
 id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.classroom_import_batches(id),
 imported_by uuid not null references auth.users(id), observer_id uuid not null references auth.users(id),
 source_hash text not null, page_key text not null, source_pages integer[] not null,
 visit_id uuid not null references public.classroom_visits(id), reviewed_snapshot jsonb not null,
 created_at timestamptz not null default now(), unique(source_hash,page_key,observer_id)
);
create index classroom_import_records_batch on public.classroom_import_records(batch_id);
alter table public.classroom_import_records enable row level security;
create policy import_records_read on public.classroom_import_records for select to authenticated using(imported_by=(select auth.uid()) and observation_private.can_import_visits());
revoke all on public.classroom_import_records from public,anon,authenticated;
grant select on public.classroom_import_records to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('classroom-visit-imports','classroom-visit-imports',false,52428800,array['application/pdf'])
on conflict(id) do nothing;
create policy classroom_pdf_owner_read on storage.objects for select to authenticated using(bucket_id='classroom-visit-imports' and (storage.foldername(name))[1]=(select auth.uid())::text and observation_private.can_import_visits());
create policy classroom_pdf_owner_insert on storage.objects for insert to authenticated with check(bucket_id='classroom-visit-imports' and (storage.foldername(name))[1]=(select auth.uid())::text and observation_private.can_import_visits() and exists(select 1 from public.classroom_import_batches b where b.user_id=auth.uid() and b.storage_path=name));

create or replace function observation_private.import_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not observation_private.can_import_visits() then raise exception 'لا توجد صلاحية لاستيراد الزيارات' using errcode='42501'; end if;
 return jsonb_build_object('teachers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'department',department,'academic_year',academic_year) order by full_name),'[]') from public.observation_teachers where active and observation_private.teacher_access(id,true,0)),
 'observers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'role',role) order by full_name),'[]') from public.profiles where role in ('principal','assistant_principal','first_teacher','coordinator')));
end $$;
create or replace function public.classroom_import_context() returns jsonb language sql security invoker set search_path='' as $$ select observation_private.import_context() $$;

-- Serialize attempts per user; never accept a browser-supplied counter.
create or replace function observation_private.claim_pdf_extraction(batch uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not observation_private.can_import_visits() then raise exception 'لا توجد صلاحية' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pdf-extract:'||auth.uid()::text,0));
 if (select coalesce(sum(extraction_calls),0) from public.classroom_import_batches where user_id=auth.uid() and created_at>now()-interval '24 hours')>=100 then raise exception 'وصلتِ إلى الحد اليومي لمعالجة الملفات. حاولي غدًا.'; end if;
 update public.classroom_import_batches set extraction_calls=extraction_calls+1 where id=batch and user_id=auth.uid() and extraction_calls<60;
 if not found then raise exception 'ملف غير متاح أو تجاوز عدد المحاولات'; end if;
 return true;
end $$;
create or replace function public.claim_classroom_pdf_extraction(batch uuid) returns boolean language sql security invoker set search_path='' as $$ select observation_private.claim_pdf_extraction(batch) $$;

create or replace function observation_private.commit_pdf_visit(batch uuid, source_pages integer[], payload jsonb, ratings jsonb, details jsonb, reviewed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b public.classroom_import_batches; obs public.profiles; tid uuid; old_visit uuid; result jsonb; v_page_key text; p integer; vid uuid;
begin
 if not observation_private.can_import_visits() or reviewed is distinct from true then raise exception 'راجعي الاستمارة وأكدي مطابقة البيانات أولًا' using errcode='42501'; end if;
 select * into b from public.classroom_import_batches where id=batch and user_id=auth.uid();
 if b.id is null then raise exception 'ملف غير متاح' using errcode='42501'; end if;
 if cardinality(source_pages) is null or cardinality(source_pages) not between 1 and 4 or cardinality(source_pages)<>(select count(distinct n) from unnest(source_pages)n) then raise exception 'صفحات المصدر غير صالحة'; end if;
 foreach p in array source_pages loop if p is null or p<1 or p>b.page_count then raise exception 'رقم صفحة غير صالح'; end if; end loop;
 select string_agg(n::text,',' order by n) into v_page_key from unnest(source_pages)n;
 tid:=(payload->>'teacher_id')::uuid;
 if not observation_private.teacher_access(tid,true,0) then raise exception 'القسم غير مسموح لحسابك' using errcode='42501'; end if;
 select * into obs from public.profiles where id=(payload->>'observer_id')::uuid and role in ('principal','assistant_principal','first_teacher','coordinator');
 if obs.id is null then raise exception 'اختاري الزائرة الصحيحة من القائمة'; end if;
 if nullif(btrim(payload->>'class_section'),'') is null or nullif(btrim(payload->>'lesson_title'),'') is null or payload->>'status'<>'final' then raise exception 'أكملي الصف وعنوان الدرس قبل الاعتماد'; end if;
 if jsonb_array_length(ratings)<>18 or exists(select 1 from jsonb_array_elements(ratings)x where (x->>'level') is null or (x->>'level')::int not between 1 and 4) then raise exception 'راجعي تقييم المعايير الثمانية عشر'; end if;
 perform pg_advisory_xact_lock(hashtextextended(tid::text||obs.id::text||(payload->>'visit_date'),0));
 select visit_id into old_visit from public.classroom_import_records r where r.source_hash=b.source_hash and r.page_key=v_page_key and r.observer_id=obs.id;
 if old_visit is not null then return jsonb_build_object('duplicate',true,'id',old_visit); end if;
 -- Missing class/period in older records must not allow duplicates. Different observers remain independent.
 select v.id into old_visit from public.classroom_visits v where v.teacher_id=tid and v.observer_id=obs.id and v.visit_date=(payload->>'visit_date')::date
 and regexp_replace(v.lesson_title,'[[:space:]،,.ـ]','','g')=regexp_replace(payload->>'lesson_title','[[:space:]،,.ـ]','','g')
 and (v.class_section='' or payload->>'class_section'='' or regexp_replace(v.class_section,'[[:space:]/]','','g')=regexp_replace(payload->>'class_section','[[:space:]/]','','g')) limit 1;
 if old_visit is not null then return jsonb_build_object('duplicate',true,'id',old_visit); end if;
 -- A near match is stopped for inspection rather than silently counted twice.
 if exists(select 1 from public.classroom_visits v where v.teacher_id=tid and v.observer_id=obs.id and v.visit_date=(payload->>'visit_date')::date and (v.lesson_period='' or payload->>'lesson_period'='' or v.lesson_period=payload->>'lesson_period')) then
  return jsonb_build_object('possible_duplicate',true,'message','توجد زيارة للمعلمة والزائرة في التاريخ والحصة نفسيهما. راجعي سجل الزيارات قبل الإدخال.');
 end if;
 details:=details||jsonb_build_object('support_notes',coalesce(details->>'support_notes','')||E'\nالمصدر: '||b.file_name||' — الصفحات: '||v_page_key||E'\nراجعت البيانات واعتمدتها: '||(select full_name from public.profiles where id=auth.uid()));
 payload:=(payload-'id'-'request_id')||jsonb_build_object('status','final','request_id',gen_random_uuid());
 result:=observation_private.save_visit(payload,ratings,details,null);
 vid:=(result->>'id')::uuid;
 update public.classroom_visits set observer_id=obs.id,observer_name=obs.full_name,observer_role=obs.role where id=vid;
 insert into public.classroom_import_records(batch_id,imported_by,observer_id,source_hash,page_key,source_pages,visit_id,reviewed_snapshot)
 values(b.id,auth.uid(),obs.id,b.source_hash,v_page_key,source_pages,vid,jsonb_build_object('payload',payload,'ratings',ratings,'details',details));
 return result||jsonb_build_object('duplicate',false);
end $$;
create or replace function public.commit_classroom_pdf_visit(batch uuid, source_pages integer[], payload jsonb, ratings jsonb, details jsonb, reviewed boolean) returns jsonb
language sql security invoker set search_path='' as $$select observation_private.commit_pdf_visit(batch,source_pages,payload,ratings,details,reviewed)$$;

revoke all on function observation_private.import_context(),observation_private.claim_pdf_extraction(uuid),observation_private.commit_pdf_visit(uuid,integer[],jsonb,jsonb,jsonb,boolean) from public,anon;
revoke all on function public.classroom_import_context(),public.claim_classroom_pdf_extraction(uuid),public.commit_classroom_pdf_visit(uuid,integer[],jsonb,jsonb,jsonb,boolean) from public,anon;
grant execute on function observation_private.import_context(),observation_private.claim_pdf_extraction(uuid),observation_private.commit_pdf_visit(uuid,integer[],jsonb,jsonb,jsonb,boolean) to authenticated;
grant execute on function public.classroom_import_context(),public.claim_classroom_pdf_extraction(uuid),public.commit_classroom_pdf_visit(uuid,integer[],jsonb,jsonb,jsonb,boolean) to authenticated;
commit;
