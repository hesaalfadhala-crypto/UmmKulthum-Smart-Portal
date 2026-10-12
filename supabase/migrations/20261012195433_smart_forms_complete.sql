-- Extend existing forms. No accounts, legacy submissions, or grants are rewritten.
create schema forms_private;
revoke all on schema forms_private from public,anon;
grant usage on schema forms_private to anon,authenticated;
alter table public.forms add column public_id uuid default gen_random_uuid() unique,
 add column questions jsonb not null default '[]',add column published_questions jsonb not null default '[]',
 add column scope text not null default 'internal' check(scope in('internal','public')),
 add column public_enabled boolean not null default false,add column multiple_responses boolean not null default false,
 add column target_count integer check(target_count between 1 and 100000),add column department text not null default '',
 add column version integer not null default 1,add column published_version integer not null default 0,
 add column client_request_id uuid,add constraint forms_save_request unique(created_by,client_request_id);
create table public.form_responses (
 id uuid primary key,form_id bigint not null references public.forms(id),respondent_id uuid references auth.users(id),
 respondent_key text not null,department text not null default '',answers jsonb not null,schema_snapshot jsonb not null,
 published_version integer not null,created_at timestamptz not null default now()
);
create index form_responses_form_date on public.form_responses(form_id,created_at,id);
create index form_responses_identity on public.form_responses(form_id,respondent_key);
create table forms_private.uploads (
 id uuid primary key default gen_random_uuid(),form_id bigint not null references public.forms(id),
 request_id uuid not null,question_id uuid not null,respondent_key text not null,path text not null unique,
 original_name text not null,mime_type text not null,expected_bytes integer not null check(expected_bytes between 1 and 8388608),
 response_id uuid references public.form_responses(id),expires_at timestamptz not null default now()+interval '1 hour',
 created_at timestamptz not null default now()
);
alter table forms_private.uploads enable row level security;
revoke all on forms_private.uploads from public,anon,authenticated;
create function forms_private.member() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid() and lower(u.email) like '%@moe.bh' and u.email_confirmed_at is not null)
$$;
create function forms_private.admin() returns boolean language sql stable security definer set search_path='' as $$
 select forms_private.member() and exists(select 1 from public.profiles where id=auth.uid() and school_access='all' and role in('principal','assistant_principal'))
$$;
create function forms_private.manages(fid bigint) returns boolean language sql stable security definer set search_path='' as $$
 select forms_private.member() and exists(select 1 from public.forms f where f.id=fid and
 (f.created_by=auth.uid() or forms_private.admin() or exists(select 1 from public.profiles p join public.observation_access a on a.user_id=p.id where p.id=auth.uid() and p.role in('assistant_principal','first_teacher','coordinator') and a.department=f.department and a.can_edit)))
$$;
create function forms_private.edits(fid bigint) returns boolean language sql stable security definer set search_path='' as $$
 select forms_private.member() and exists(select 1 from public.forms where id=fid and (created_by=auth.uid() or forms_private.admin()))
$$;
create function forms_private.key(device_token uuid) returns text language sql stable set search_path='' as $$
 select case when auth.uid() is not null then 'user:'||auth.uid()::text when device_token is not null then 'device:'||encode(sha256(convert_to(device_token::text,'UTF8')),'hex') else null end
$$;
create function forms_private.validate_questions(qs jsonb) returns void language plpgsql immutable set search_path='' as $$
declare q jsonb; v jsonb;
begin
 if jsonb_typeof(qs) is distinct from 'array' or jsonb_array_length(qs)>50 then raise exception 'حد النموذج 50 سؤالًا.';end if;
 for q in select * from jsonb_array_elements(qs) loop
  if jsonb_typeof(q)<>'object' or q-array['id','title','type','required','options']<>'{}' or coalesce(q->>'id','')!~'^[a-f0-9-]{36}$' or length(btrim(coalesce(q->>'title',''))) not between 1 and 500 or coalesce(q->>'type','') not in('choice','checkbox','short','long','dropdown','rating','date','file') or jsonb_typeof(q->'required') is distinct from 'boolean' then raise exception 'راجعي السؤال ونوعه وعنوانه.';end if;
  if q->>'type' in('choice','checkbox','dropdown') then
   if jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options') not between 2 and 100 then raise exception 'أضيفي خيارين على الأقل.';end if;
   for v in select * from jsonb_array_elements(q->'options') loop if jsonb_typeof(v)<>'string' or length(btrim(v#>>'{}')) not between 1 and 200 then raise exception 'أحد خيارات السؤال غير صالح.';end if;end loop;
   if exists(select 1 from jsonb_array_elements_text(q->'options') value group by value having count(*)>1) then raise exception 'خيارات السؤال مكررة.';end if;
  end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(qs) item group by item->>'id' having count(*)>1) then raise exception 'معرف السؤال مكرر.';end if;
end $$;
create function forms_private.save(payload jsonb,expected_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.forms;fid bigint;request_uuid uuid:=nullif(payload->>'request_id','')::uuid;enabled boolean;
begin
 if not forms_private.member() then raise exception 'يلزم حساب وزاري معتمد.' using errcode='42501';end if;
 if length(btrim(coalesce(payload->>'title',''))) not between 1 and 300 or length(coalesce(payload->>'description',''))>6000 or length(coalesce(payload->>'target_audience',''))>500 then raise exception 'راجعي عنوان النموذج ووصفه.';end if;
 perform forms_private.validate_questions(payload->'questions');
 if coalesce(payload->>'scope','internal') not in('internal','public') then raise exception 'نوع النموذج غير صالح.';end if;
 if nullif(payload->>'id','') is not null then
  fid:=(payload->>'id')::bigint;select * into f from public.forms where id=fid for update;
  if not found or not forms_private.edits(fid) then raise exception 'النموذج غير متاح للتعديل.' using errcode='42501';end if;
  if f.version is distinct from expected_version then raise exception 'تم تعديل النموذج من جلسة أخرى. أعيدي تحميله.' using errcode='40001';end if;
 else
  if request_uuid is null or expected_version<>0 then raise exception 'معرف الحفظ مطلوب.';end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||request_uuid::text,1));
  select * into f from public.forms where created_by=auth.uid() and client_request_id=request_uuid;
  if found then return jsonb_build_object('id',f.id,'version',f.version,'public_id',f.public_id,'recovered',true);end if;
  insert into public.forms(title,created_by,client_request_id,status) values(payload->>'title',auth.uid(),request_uuid,'draft') returning * into f;fid:=f.id;
 end if;
 enabled:=case when forms_private.admin() then coalesce((payload->>'public_enabled')::boolean,false) else f.public_enabled and f.scope=coalesce(payload->>'scope','internal') end;
 update public.forms set title=payload->>'title',description=coalesce(payload->>'description',''),target_audience=coalesce(payload->>'target_audience',''),questions=payload->'questions',scope=coalesce(payload->>'scope','internal'),public_enabled=enabled,multiple_responses=coalesce((payload->>'multiple_responses')::boolean,false),target_count=nullif(payload->>'target_count','')::integer,department=coalesce(payload->>'department',''),closing_date=nullif(payload->>'closing_date','')::timestamptz,public_id=coalesce(public_id,gen_random_uuid()),version=case when expected_version=0 then 1 else version+1 end,updated_at=now() where id=fid returning * into f;
 return jsonb_build_object('id',f.id,'version',f.version,'public_id',f.public_id);
end $$;
create function forms_private.publish(form_id bigint,action text,expected_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.forms;
begin
 select * into f from public.forms where id=form_id for update;
 if not found or not forms_private.edits(form_id) then raise exception 'ليست لديكِ صلاحية إدارة هذا النموذج.' using errcode='42501';end if;
 if f.version is distinct from expected_version then raise exception 'حدّثي النموذج قبل النشر.' using errcode='40001';end if;
 if action in('publish','reopen') then
  if f.scope='public' and not f.public_enabled then raise exception 'النموذج العام يحتاج موافقة الإدارة.' using errcode='42501';end if;
  if jsonb_array_length(f.questions)=0 then raise exception 'أضيفي سؤالًا واحدًا على الأقل.';end if;
  update public.forms set status='published',published_questions=case when action='publish' or published_version=0 then questions else published_questions end,published_version=case when action='publish' or published_version=0 then published_version+1 else published_version end,closing_date=case when action='reopen' and closing_date<=now() then null else closing_date end,version=version+1,updated_at=now() where id=form_id returning * into f;
 elsif action='close' then update public.forms set status='closed',version=version+1,updated_at=now() where id=form_id returning * into f;
 else raise exception 'الإجراء غير صالح.';end if;
 return jsonb_build_object('id',f.id,'version',f.version,'public_id',f.public_id,'status',f.status);
end $$;
create function forms_private.open(slug uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f public.forms;
begin
 select * into f from public.forms where public_id=slug and status in('published','closed');
 if not found or (f.scope='public' and not f.public_enabled) then raise exception 'النموذج غير متاح.' using errcode='42501';end if;
 if f.scope='internal' and not forms_private.member() then raise exception 'هذا نموذج داخلي. سجّلي الدخول بالإيميل الوزاري.' using errcode='42501';end if;
 return jsonb_build_object('title',f.title,'description',f.description,'target_audience',f.target_audience,'scope',f.scope,'questions',f.published_questions,'multiple_responses',f.multiple_responses,'closing_date',f.closing_date,'accepting',f.status='published' and(f.closing_date is null or f.closing_date>now()),'version',f.published_version);
end $$;
create function forms_private.prepare_upload(slug uuid,request_uuid uuid,question_uuid uuid,device_token uuid,original_name text,mime_type text,byte_count integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.forms;key text:=forms_private.key(device_token);fid uuid:=gen_random_uuid();ext text;path text;
begin
 perform forms_private.open(slug);select * into f from public.forms where public_id=slug;
 if f.status<>'published' or f.closing_date<=now() or key is null then raise exception 'النموذج مغلق.';end if;
 if not exists(select 1 from jsonb_array_elements(f.published_questions) q where q->>'id'=question_uuid::text and q->>'type'='file') then raise exception 'سؤال الملف غير موجود.';end if;
 if byte_count not between 1 and 8388608 or length(original_name) not between 1 and 250 then raise exception 'حد الملف 8 ميغابايت.';end if;
 ext:=case mime_type when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png' else null end;
 if ext is null then raise exception 'الملفات المقبولة PDF وJPG وPNG.';end if;
 if exists(select 1 from public.form_responses where id=request_uuid) or (select count(*) from forms_private.uploads where form_id=f.id and created_at>now()-interval '1 hour')>=100 or (select count(*) from forms_private.uploads where form_id=f.id and request_id=request_uuid)>=5 then raise exception 'تجاوزتِ حد الرفع. أعيدي المحاولة لاحقًا.';end if;
 path:=slug::text||'/'||request_uuid::text||'/'||fid::text||'.'||ext;
 insert into forms_private.uploads(id,form_id,request_id,question_id,respondent_key,path,original_name,mime_type,expected_bytes) values(fid,f.id,request_uuid,question_uuid,key,path,original_name,mime_type,byte_count);
 return jsonb_build_object('path',path,'id',fid);
end $$;
create function forms_private.storage_upload(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from forms_private.uploads u join public.forms f on f.id=u.form_id where u.path=storage_upload.path and u.expires_at>now() and u.response_id is null and f.status='published' and(f.closing_date is null or f.closing_date>now()) and ((f.scope='public' and f.public_enabled) or(f.scope='internal' and forms_private.member() and u.respondent_key=forms_private.key(null))))
$$;
create function forms_private.storage_read(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from forms_private.uploads u where u.path=storage_read.path and u.response_id is not null and forms_private.manages(u.form_id))
$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('school-form-files','school-form-files',false,8388608,array['application/pdf','image/jpeg','image/png']);
create policy form_files_upload on storage.objects for insert to anon,authenticated with check(bucket_id='school-form-files' and forms_private.storage_upload(name));
create policy form_files_read on storage.objects for select to authenticated using(bucket_id='school-form-files' and forms_private.storage_read(name));
create function forms_private.submit(slug uuid,response_uuid uuid,answers jsonb,device_token uuid,department text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.forms;q jsonb;v jsonb;k text:=forms_private.key(device_token);prior public.form_responses;v_text text;declared text:=department;
begin
 perform forms_private.open(slug);select * into f from public.forms where public_id=slug for update;
 if f.status<>'published' or f.closing_date<=now() or k is null or response_uuid is null then raise exception 'النموذج مغلق أو المحاولة غير صالحة.';end if;
 if jsonb_typeof(answers) is distinct from 'object' or octet_length(answers::text)>100000 or length(department)>180 then raise exception 'بيانات الإجابة غير صالحة.';end if;
 select * into prior from public.form_responses where id=response_uuid;
 if found then if prior.form_id<>f.id or prior.respondent_key<>k or prior.answers<>answers then raise exception 'معرف المحاولة غير متاح.';end if;return jsonb_build_object('id',prior.id,'saved',true,'recovered',true);end if;
 if not f.multiple_responses and exists(select 1 from public.form_responses where form_id=f.id and respondent_key=k) then raise exception 'تم إرسال استجابتكِ سابقًا. يسمح النموذج باستجابة واحدة.' using errcode='23505';end if;
 if exists(select 1 from jsonb_object_keys(answers) key where not exists(select 1 from jsonb_array_elements(f.published_questions) item where item->>'id'=key)) then raise exception 'الإجابة تحتوي سؤالًا غير موجود.';end if;
 for q in select * from jsonb_array_elements(f.published_questions) loop
  v:=answers->(q->>'id');
  if v is null or v='null' or v='""' or v='[]' then if (q->>'required')::boolean then raise exception 'أجيبي عن السؤال الإجباري: %',q->>'title';else continue;end if;end if;
  if q->>'type' in('short','long') then if jsonb_typeof(v)<>'string' or length(v#>>'{}')>(case when q->>'type'='short' then 500 else 6000 end) or ((q->>'required')::boolean and btrim(v#>>'{}')='') then raise exception 'الإجابة النصية غير صالحة.';end if;
  elsif q->>'type' in('choice','dropdown') then if jsonb_typeof(v)<>'string' or not(q->'options' @> jsonb_build_array(v)) then raise exception 'اختاري إجابة من الخيارات.';end if;
  elsif q->>'type'='checkbox' then if jsonb_typeof(v)<>'array' or not(q->'options' @> v) or jsonb_array_length(v)<> (select count(distinct value) from jsonb_array_elements(v)) then raise exception 'اختيارات السؤال غير صالحة.';end if;
  elsif q->>'type'='rating' then if jsonb_typeof(v)<>'number' or (v#>>'{}')!~'^[1-5]$' then raise exception 'التقييم يكون من 1 إلى 5.';end if;
  elsif q->>'type'='date' then if jsonb_typeof(v)<>'string' or (v#>>'{}')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'التاريخ غير صالح.';end if;perform (v#>>'{}')::date;
  elsif q->>'type'='file' then
   if jsonb_typeof(v)<>'object' or not exists(select 1 from forms_private.uploads u join storage.objects o on o.bucket_id='school-form-files' and o.name=u.path where u.form_id=f.id and u.request_id=response_uuid and u.question_id=(q->>'id')::uuid and u.path=v->>'path' and u.respondent_key=k and u.response_id is null and u.expires_at>now() and coalesce((o.metadata->>'size')::bigint,0)<=8388608) then raise exception 'ارفعي ملفًا صالحًا لهذا السؤال.';end if;
  end if;
 end loop;
 if f.scope='internal' then select coalesce(nullif(p.department,''),declared) into declared from public.profiles p where id=auth.uid();end if;
 insert into public.form_responses(id,form_id,respondent_id,respondent_key,department,answers,schema_snapshot,published_version) values(response_uuid,f.id,auth.uid(),k,coalesce(declared,''),answers,f.published_questions,f.published_version);
 update forms_private.uploads set response_id=response_uuid where form_id=f.id and request_id=response_uuid and respondent_key=k and path in(select value->>'path' from jsonb_each(answers) where jsonb_typeof(value)='object');
 return jsonb_build_object('id',response_uuid,'saved',true);
end $$;
alter table public.form_responses enable row level security;
revoke all on public.form_responses from public,anon,authenticated;grant select on public.form_responses to authenticated;
create policy form_results_permitted on public.form_responses for select to authenticated using(forms_private.manages(form_id));
drop policy "Authenticated users can create forms" on public.forms;
drop policy "Users can update own forms" on public.forms;
drop policy "Users can view permitted forms" on public.forms;
revoke insert,update,delete on public.forms from anon,authenticated;
create policy smart_forms_management_read on public.forms for select to authenticated using(forms_private.manages(id));
create function public.smart_forms_context() returns jsonb language sql stable security invoker set search_path='' as $$select jsonb_build_object('member',forms_private.member(),'admin',forms_private.admin())$$;
create function public.save_smart_form(payload jsonb,expected_version integer) returns jsonb language sql security invoker set search_path='' as $$select forms_private.save(payload,expected_version)$$;
create function public.publish_smart_form(form_id bigint,action text,expected_version integer) returns jsonb language sql security invoker set search_path='' as $$select forms_private.publish(form_id,action,expected_version)$$;
create function public.open_smart_form(slug uuid) returns jsonb language sql security invoker set search_path='' as $$select forms_private.open(slug)$$;
create function public.prepare_form_upload(slug uuid,request_uuid uuid,question_uuid uuid,device_token uuid,original_name text,mime_type text,byte_count integer) returns jsonb language sql security invoker set search_path='' as $$select forms_private.prepare_upload(slug,request_uuid,question_uuid,device_token,original_name,mime_type,byte_count)$$;
create function public.submit_smart_form(slug uuid,response_uuid uuid,answers jsonb,device_token uuid,department text default '') returns jsonb language sql security invoker set search_path='' as $$select forms_private.submit(slug,response_uuid,answers,device_token,department)$$;
revoke all on all functions in schema forms_private from public,anon,authenticated;
grant execute on function forms_private.member(),forms_private.admin(),forms_private.manages(bigint),forms_private.edits(bigint),forms_private.key(uuid),forms_private.storage_upload(text),forms_private.storage_read(text) to authenticated;
grant execute on function forms_private.member(),forms_private.key(uuid),forms_private.storage_upload(text) to anon;
revoke all on function public.save_smart_form(jsonb,integer),public.publish_smart_form(bigint,text,integer),public.smart_forms_context() from public,anon;
grant execute on function public.save_smart_form(jsonb,integer),public.publish_smart_form(bigint,text,integer),public.smart_forms_context() to authenticated;
revoke all on function public.open_smart_form(uuid),public.submit_smart_form(uuid,uuid,jsonb,uuid,text),public.prepare_form_upload(uuid,uuid,uuid,uuid,text,text,integer) from public;
grant execute on function public.open_smart_form(uuid),public.submit_smart_form(uuid,uuid,jsonb,uuid,text),public.prepare_form_upload(uuid,uuid,uuid,uuid,text,text,integer) to anon,authenticated;

grant execute on function forms_private.save(jsonb,integer),forms_private.publish(bigint,text,integer) to authenticated;
grant execute on function forms_private.open(uuid),forms_private.prepare_upload(uuid,uuid,uuid,uuid,text,text,integer),forms_private.submit(uuid,uuid,jsonb,uuid,text) to anon,authenticated;
