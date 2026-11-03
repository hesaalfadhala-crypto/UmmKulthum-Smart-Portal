-- Single original documentation record. No existing reports are rewritten.
create or replace function documentation_private.validate_professional_session()
returns trigger language plpgsql security definer set search_path='' as $$
declare p jsonb;t public.profiles;l public.profiles;teacher_id uuid;leader_id uuid;owner_name text;dept text;
begin
 if new.activity_type is distinct from 'جلسة التطوير المهني' then return new;end if;
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول.' using errcode='42501';end if;
 p:=new.details->'professionalSession';
 if coalesce(jsonb_typeof(p),'')<>'object' or coalesce(p->>'schemaVersion','')<>'1' then raise exception 'بيانات جلسة التطوير المهني غير مكتملة.';end if;
 begin teacher_id:=(p->'teacher'->>'id')::uuid;leader_id:=(p->'leader'->>'id')::uuid;exception when others then raise exception 'اختاري المعلمة وقائد الجلسة من الحسابات المعتمدة.';end;
 select * into t from public.profiles where id=teacher_id;if not found then raise exception 'حساب المعلمة غير متاح.';end if;
 select * into l from public.profiles where id=leader_id;if not found then raise exception 'حساب قائد الجلسة غير متاح.';end if;
 if new.activity_date is null or coalesce(new.semester,'') not in('الفصل الدراسي الأول','الفصل الدراسي الثاني') or coalesce(new.details->>'academicYear','')!~'^20[0-9]{2}-20[0-9]{2}$' then raise exception 'أكملي التاريخ والفصل والعام الدراسي.';end if;
 if coalesce(p->>'number','')!~'^[0-9]{1,5}$' then raise exception 'رقم الجلسة غير صالح.';end if;
 if (p->>'number')::integer not between 1 and 10000 then raise exception 'رقم الجلسة يجب أن يكون بين 1 و10000.';end if;
 if coalesce(jsonb_typeof(p->'goals'),'')<>'array' then raise exception 'راجعي أهداف الجلسة.';end if;
 if exists(select 1 from jsonb_array_elements(p->'goals') x where jsonb_typeof(x)<>'number' or x::text!~'^([1-9]|1[0-2])$') then raise exception 'هدف غير معتمد.';end if;
 if (select count(*)<>count(distinct x) from jsonb_array_elements(p->'goals') x) then raise exception 'لا تكرري الهدف.';end if;
 if (p->'goals')@>'[12]'::jsonb and nullif(btrim(p->>'otherGoal'),'') is null then raise exception 'اكتبي الهدف الآخر.';end if;
 if coalesce(p->>'followUpSupervisorId','') not in('','assistant','aisha','hiba') then raise exception 'اختاري المديرة المساعدة من القائمة المعتمدة.';end if;
 if greatest(length(coalesce(p->>'discussion','')),length(coalesce(p->>'recommendations','')))>20000 or length(coalesce(p->>'otherGoal',''))>1000 then raise exception 'النص أطول من حد الحفظ المسموح.';end if;
 dept:=coalesce(nullif(t.department,''),t.departments[1],'');
 if documentation_private.can_manage() and nullif(btrim(new.department),'') is not null then dept:=btrim(new.department);end if;
 new.department:=dept;new.executor:=l.full_name;
 p:=jsonb_set(p,'{teacher}',jsonb_build_object('id',t.id,'name',t.full_name,'department',dept));
 p:=jsonb_set(p,'{leader}',jsonb_build_object('id',l.id,'name',l.full_name));
 select full_name into owner_name from public.profiles where id=new.created_by;
 new.details:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(new.details,'{professionalSession}',p),'{department}',to_jsonb(dept)),'{reportPreparedBy}',to_jsonb(coalesce(owner_name,''))),'{type}','"جلسة التطوير المهني"'::jsonb);
 new.activity:='جلسة التطوير المهني — '||t.full_name||' — '||(p->>'number');
 return new;
end$$;
revoke all on function documentation_private.validate_professional_session() from public,anon,authenticated;
create trigger zz_professional_session_validation before insert or update on public.documentations for each row execute function documentation_private.validate_professional_session();
create policy support_professional_sessions_read on public.documentations for select to authenticated using(
 activity_type='جلسة التطوير المهني' and status='published' and deleted_at is null and (select support_private.reports_reader())
);
create index documentation_professional_session_date on public.documentations(activity_date,id) where activity_type='جلسة التطوير المهني';
