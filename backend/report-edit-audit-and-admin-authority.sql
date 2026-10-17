-- Retain the existing delete authority and delegated center scope.
create or replace function documentation_private.can_edit_report(owner_id uuid,typ text,dept text,removed timestamptz) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and removed is null and (
 (owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid()))
 or documentation_private.can_manage()
 or exists(select 1 from documentation_private.report_editors e where e.user_id=auth.uid() and e.manage_center and support_private.manager() and (dept='مركز الدعم والتطوير المهني' or typ='ورشة تدريبية'))
)
$$;
alter table public.documentations add column if not exists edited_by_name text;
create or replace function documentation_private.stamp_report_editor_name() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.last_edit_request is distinct from old.last_edit_request then
  new.edited_by_name:=(select p.full_name from public.profiles p where p.id=auth.uid());
 end if;
 return new;
end $$;
revoke all on function documentation_private.stamp_report_editor_name() from public,anon,authenticated;
create trigger documentation_edit_actor_name before update of last_edit_request on public.documentations for each row execute function documentation_private.stamp_report_editor_name();

