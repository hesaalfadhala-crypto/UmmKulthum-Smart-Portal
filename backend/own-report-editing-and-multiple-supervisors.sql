create or replace function documentation_private.can_edit_report(owner_id uuid,typ text,dept text,removed timestamptz) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and removed is null and (
 (owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid()))
 or exists(select 1 from documentation_private.report_editors e where e.user_id=auth.uid() and e.manage_center and support_private.manager() and (dept='مركز الدعم والتطوير المهني' or typ='ورشة تدريبية'))
)
$$;
alter table public.documentations add constraint documentation_report_supervisors_valid check (
not(details ? 'reportSupervisors') or case when jsonb_typeof(details->'reportSupervisors')='array' then jsonb_array_length(details->'reportSupervisors')<=4 and details->'reportSupervisors' <@ '["assistant","aisha","hiba","services"]'::jsonb else false end
);
