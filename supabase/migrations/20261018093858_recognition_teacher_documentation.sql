-- Enable own recognition documentation for existing school accounts only.
-- Keep the separate whole-school read delegation and administrator delete authority unchanged.
create or replace function documentation_private.recognition_allowed(writing boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
  documentation_private.can_manage()
  or (writing and exists(select 1 from public.profiles p where p.id=auth.uid()))
  or exists(select 1 from documentation_private.recognition_access a where a.user_id=auth.uid() and case when writing then a.can_write else a.can_read or a.can_write end)
 )
$$;
alter policy recognition_visibility_guard on public.documentations using(
 not documentation_private.is_recognition(details,projects)
 or (created_by=(select auth.uid()) and deleted_at is null)
 or (select documentation_private.recognition_allowed(false))
);
-- Do not add a broad SELECT policy: ownership/leadership/delegate policies still decide which rows are visible.
create or replace function public.recognition_context() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('can_write',documentation_private.recognition_allowed(true),'can_read',documentation_private.recognition_allowed(true) or documentation_private.recognition_allowed(false),'can_read_all',documentation_private.recognition_allowed(false))
$$;
revoke all on function documentation_private.recognition_allowed(boolean) from public,anon;
grant execute on function documentation_private.recognition_allowed(boolean) to authenticated;
revoke all on function public.recognition_context() from public,anon;
grant execute on function public.recognition_context() to authenticated;
