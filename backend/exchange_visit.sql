-- Applies only to the new versioned general-documentation exchange form.
-- Existing rows and supervisory classroom visits are never migrated or updated.
create or replace function documentation_private.validate_exchange_visit() returns trigger
language plpgsql security definer set search_path='' as $$
declare v jsonb:=new.details->'exchangeVisit'; visitor public.profiles; visited public.profiles; coordinator public.profiles; actor public.profiles; old_follow text:=''; allowed_ids text[]:=array['d1c1','d1c2','d1c3','d2c1','d2c2','d2c3','d2c4','d3c1','d3c2','d4c1','d4c2','d5c1','d5c2','d5c3','d5c4'];
begin
 if new.activity_type not in ('زيارة','زيارة صفية','زيارة صفية تبادلية') or v is null then return new;end if;
 if auth.uid() is null then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 select * into actor from public.profiles where id=auth.uid();
 select * into visitor from public.profiles where id=(v->>'visitorId')::uuid;
 select * into visited from public.profiles where id=(v->>'visitedId')::uuid;
 if visitor.id is null or visited.id is null then raise exception 'اختاري المعلمة الزائرة والمزارة من الحسابات المسجلة.';end if;
 if actor.role not in ('principal','assistant_principal') and visitor.id<>new.created_by then raise exception 'لا يمكن تغيير هوية المعلمة الزائرة.' using errcode='42501';end if;
 if tg_op='UPDATE' then old_follow:=coalesce(old.details->'exchangeVisit'->>'followUp','');end if;
 if actor.role not in ('principal','assistant_principal') and coalesce(v->>'followUp','')<>old_follow then raise exception 'متابعة المديرة المساعدة متاحة للإدارة فقط.' using errcode='42501';end if;
 if new.department is null or not (new.department=visitor.department or new.department=any(coalesce(visitor.departments,'{}'))) then raise exception 'اختاري قسم المعلمة الزائرة المعتمد.';end if;
 if coalesce(v->>'kind','') not in ('داخل القسم','خارج القسم') or new.activity_date is null or nullif(btrim(new.semester),'') is null or coalesce(new.details->>'academicYear','')!~'^20[0-9]{2}-20[0-9]{2}$' then raise exception 'أكملي بيانات الزيارة.';end if;
 if coalesce(length(btrim(v->>'lessonTitle')),0) not between 1 and 300 or coalesce(length(btrim(v->>'subject')),0) not between 1 and 300 or coalesce(length(btrim(v->>'className')),0) not between 1 and 300 or coalesce(length(btrim(v->>'practices')),0) not between 1 and 20000 or length(coalesce(v->>'followUp',''))>10000 then raise exception 'أكملي عنوان الدرس والمادة والصف والممارسات المستفادة.';end if;
 if jsonb_typeof(v->'selected') is distinct from 'array' then raise exception 'اختيارات الممارسات غير صالحة.';end if;
 if exists(select 1 from jsonb_array_elements_text(v->'selected') x where not x=any(allowed_ids)) or (select count(distinct x) from jsonb_array_elements_text(v->'selected') x)<>jsonb_array_length(v->'selected') then raise exception 'راجعي الممارسات المختارة.';end if;
 if nullif(v->>'coordinatorId','') is not null then
 select * into coordinator from public.profiles where id=(v->>'coordinatorId')::uuid;
 if coordinator.id is null or (coordinator.role not in ('first_teacher','coordinator','principal','assistant_principal') and coalesce(coordinator.job_title,'')!~'(أول|اول|منسق)') then raise exception 'اختاري المعلمة الأولى أو المنسقة المعتمدة.';end if;end if;
 v:=jsonb_build_object('schemaVersion',1,'lessonTitle',btrim(v->>'lessonTitle'),'subject',btrim(v->>'subject'),'className',btrim(v->>'className'),'kind',v->>'kind','visitorId',visitor.id,'visitorName',visitor.full_name,'visitedId',visited.id,'visitedName',visited.full_name,'coordinatorId',coordinator.id,'coordinatorName',coordinator.full_name,'selected',v->'selected','practices',btrim(v->>'practices'),'followUp',coalesce(v->>'followUp',''));
 new.activity_type:='زيارة صفية';new.activity:=v->>'lessonTitle';new.executor:=visitor.full_name;
 new.details:=new.details||jsonb_build_object('type','زيارة صفية','activity',new.activity,'executor',new.executor,'reportPreparedBy',new.executor,'exchangeVisit',v);
 return new;
end $$;
revoke all on function documentation_private.validate_exchange_visit() from public,anon,authenticated;
drop trigger if exists zz_exchange_visit_validation on public.documentations;
create trigger zz_exchange_visit_validation before insert or update of details,activity_type,department,executor on public.documentations for each row execute function documentation_private.validate_exchange_visit();
