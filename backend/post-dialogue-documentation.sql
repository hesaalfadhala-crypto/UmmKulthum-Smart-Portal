-- This subtype uses the original documentation ID and the existing ownership/edit guards.
create or replace function documentation_private.validate_post_dialogue() returns trigger language plpgsql security definer set search_path='' as $$
declare p jsonb;t public.profiles;v public.profiles;owner_name text;teacher_id uuid;visitor_id uuid;
begin
 if new.activity_type is distinct from 'الحوارات البعدية للزيارات الصفية' then return new;end if;
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول.' using errcode='42501';end if;
 p:=new.details->'postDialogue';
 if jsonb_typeof(p)<>'object' or coalesce(p->>'schemaVersion','')<>'1' then raise exception 'بيانات الحوار البعدي غير مكتملة.';end if;
 begin teacher_id:=(p->'teacher'->>'id')::uuid;visitor_id:=(p->'visitor'->>'id')::uuid;exception when others then raise exception 'اختاري المعلمة والزائر من الحسابات المعتمدة.';end;
 select * into t from public.profiles where id=teacher_id;if not found then raise exception 'حساب المعلمة غير متاح.';end if;
 if visitor_id is distinct from auth.uid() and not documentation_private.can_manage() then raise exception 'اسم الزائر مرتبط بحسابكِ.' using errcode='42501';end if;
 select * into v from public.profiles where id=visitor_id;if not found then raise exception 'حساب الزائر غير متاح.';end if;
 if new.activity_date is null or coalesce(new.semester,'') not in('الفصل الدراسي الأول','الفصل الدراسي الثاني') or coalesce(new.details->>'academicYear','')!~'^20[0-9]{2}-20[0-9]{2}$' or nullif(btrim(p->>'lessonTitle'),'') is null then raise exception 'أكملي تاريخ الزيارة والفصل والعام الدراسي وعنوان الدرس.';end if;
 if nullif(p->>'visitNumber','') is not null and (p->>'visitNumber'!~'^[0-9]{1,5}$' or (p->>'visitNumber')::integer not between 1 and 10000) then raise exception 'رقم الزيارة غير صالح.';end if;
 if coalesce(p->>'followUpSupervisorId','') not in('','assistant','aisha','hiba') then raise exception 'اختاري المديرة المساعدة من القائمة المعتمدة.';end if;
 if greatest(length(coalesce(p->>'successes','')),length(coalesce(p->>'supportPlan','')))>20000 or length(coalesce(p->>'comment',''))>6000 then raise exception 'النص أطول من حد الحفظ المسموح.';end if;
 new.department:=coalesce(nullif(t.department,''),t.departments[1],'');new.executor:=v.full_name;
 p:=jsonb_set(p,'{teacher}',jsonb_build_object('id',t.id,'name',t.full_name,'department',new.department));
 p:=jsonb_set(p,'{visitor}',jsonb_build_object('id',v.id,'name',v.full_name,'jobTitle',coalesce(v.job_title,'')));
 select full_name into owner_name from public.profiles where id=new.created_by;
 new.details:=jsonb_set(jsonb_set(jsonb_set(new.details,'{postDialogue}',p),'{department}',to_jsonb(new.department)),'{reportPreparedBy}',to_jsonb(coalesce(owner_name,'')));
 new.activity:='الحوارات البعدية للزيارات الصفية — '||t.full_name;
 return new;
end$$;
revoke all on function documentation_private.validate_post_dialogue() from public,anon,authenticated;
create trigger zz_post_dialogue_validation before insert or update of details,activity_type,department,executor on public.documentations for each row execute function documentation_private.validate_post_dialogue();
create policy support_post_dialogues_read on public.documentations for select to authenticated using(
 activity_type='الحوارات البعدية للزيارات الصفية' and status='published' and deleted_at is null and (select support_private.reports_reader())
);
create index documentation_post_dialogue_date on public.documentations(activity_date,id) where activity_type='الحوارات البعدية للزيارات الصفية';
