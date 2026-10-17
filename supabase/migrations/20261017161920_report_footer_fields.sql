-- Optional JSON fields preserve all older reports and leave grants/RLS unchanged.
alter table public.documentations add constraint documentation_report_preparer_valid check (
 not (details ? 'reportPreparer') or (jsonb_typeof(details->'reportPreparer')='string' and length(btrim(details->>'reportPreparer')) between 1 and 300)
), add constraint documentation_report_supervisor_valid check (
 not (details ? 'reportSupervisor') or (jsonb_typeof(details->'reportSupervisor')='string' and details->>'reportSupervisor' in ('assistant','services'))
);
