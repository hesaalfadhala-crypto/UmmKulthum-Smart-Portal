-- Explicitly requested read-only sharing of approved leadership plans.
-- Existing editing/reviewing grants remain unchanged; drafts and review comments stay private.
create function weekly_private.private_plan_access(plan_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(select 1 from public.weekly_plans p left join public.weekly_staff s on s.id=p.staff_id where p.id=plan_uuid and
 ((p.kind='principal' and (weekly_private.full_access() or weekly_private.principal_editor())) or
 (p.kind='staff' and (s.user_id=auth.uid() or weekly_private.reviews_department(p.department)))))
$$;
revoke all on function weekly_private.private_plan_access(uuid) from public,anon;
grant execute on function weekly_private.private_plan_access(uuid) to authenticated;
create function weekly_private.shared_plan(plan_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(
 select 1 from public.weekly_plans p join public.weekly_staff s on s.id=p.staff_id
 join public.profiles owner on owner.id=s.user_id join public.profiles viewer on viewer.id=auth.uid()
 where p.id=plan_uuid and p.kind='staff' and p.status='approved' and s.active and
 (owner.role='assistant_principal' or owner.role in('first_teacher','coordinator') and nullif(btrim(p.department),'') is not null and (
 p.department=any(case when cardinality(viewer.departments)>0 then viewer.departments else array[viewer.department] end)
 or (p.department=any(owner.departments) and owner.departments && case when cardinality(viewer.departments)>0 then viewer.departments else array[viewer.department] end)
 )))
$$;
revoke all on function weekly_private.shared_plan(uuid) from public,anon;
grant execute on function weekly_private.shared_plan(uuid) to authenticated;
create or replace function weekly_private.read_plan(plan_uuid uuid) returns boolean language sql stable security invoker set search_path='' as $$
 select weekly_private.private_plan_access(plan_uuid) or weekly_private.shared_plan(plan_uuid)
$$;
create or replace function weekly_private.read_file(file_uuid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select weekly_private.registered() and exists(select 1 from public.weekly_files f where f.id=file_uuid and
 (weekly_private.private_plan_access(f.plan_id)
 or exists(select 1 from public.weekly_plans p where p.id=f.plan_id and p.file_id=f.id and weekly_private.shared_plan(p.id))
 or exists(select 1 from public.weekly_publications pp where pp.file_id=f.id)))
$$;
alter policy weekly_reviews_read on public.weekly_reviews using(weekly_private.private_plan_access(plan_id));
create function weekly_private.sharing() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not weekly_private.registered() then raise exception 'يرجى تسجيل الدخول.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('plan_id',p.id,'owner_role',pr.role)) from public.weekly_plans p join public.weekly_staff s on s.id=p.staff_id join public.profiles pr on pr.id=s.user_id where weekly_private.shared_plan(p.id)),'[]');
end $$;
revoke all on function weekly_private.sharing() from public,anon;
grant execute on function weekly_private.sharing() to authenticated;
create function public.weekly_plan_sharing() returns jsonb language sql security invoker set search_path='' as $$select weekly_private.sharing()$$;
revoke all on function public.weekly_plan_sharing() from public,anon;
grant execute on function public.weekly_plan_sharing() to authenticated;
