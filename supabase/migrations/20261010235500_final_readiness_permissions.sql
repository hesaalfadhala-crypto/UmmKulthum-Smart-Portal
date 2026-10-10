begin;
-- Authorization fields are server-managed. An owner may update her display name only.
revoke update on public.profiles from anon, authenticated, public;
revoke update (id, full_name, role, department, created_at) on public.profiles from anon, authenticated, public;
alter table public.profiles add column if not exists school_access text not null default 'own' check (school_access in ('own','all'));
revoke update (school_access) on public.profiles from anon, authenticated, public;
grant update (full_name) on public.profiles to authenticated;
-- Preserve the verified principal's previously authorized school scope.
update public.profiles p set school_access='all'
from auth.users u where u.id=p.id and p.role='principal'
and u.raw_app_meta_data->>'school_access'='principal_all';
-- The user explicitly requested full permissions for Hessa, not all assistants.
do $$ begin
 if (select count(*) from public.profiles where full_name='حصه سند الفضاله' and role='assistant_principal') <> 1 then
  raise exception 'The authorized assistant must resolve to exactly one existing profile';
 end if;
end $$;
update public.profiles set school_access='all' where full_name='حصه سند الفضاله' and role='assistant_principal';
-- Use immutable server-managed scope rather than stale JWT claims or user-editable roles.
drop policy if exists "School principal reads all documentations" on public.documentations;
create policy "Authorized school leadership reads documentations" on public.documentations for select to authenticated
using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.school_access='all'));
drop policy if exists "Users can view permitted competitions" on public.competitions;
create policy "Users can view permitted competitions" on public.competitions for select to authenticated
using (created_by=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.school_access='all'));
drop policy if exists "Authenticated users can view forms" on public.forms;
create policy "Users can view permitted forms" on public.forms for select to authenticated
using (created_by=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.school_access='all'));
commit;
