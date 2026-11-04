create function documentation_private.happiness_reader(doc bigint) returns boolean language sql stable security definer set search_path='' as $$
select (select auth.uid())='a5422c4c-4533-4b18-8103-5d0fe9e273ce'::uuid and exists(select 1 from public.documentations d where d.id=doc and d.deleted_at is null and d.activity_type is distinct from 'اجتماع' and (
d.activity_type='لجنة السعادة' or d.details->'happiness'->>'schemaVersion'='1' or d.details->'committees' ? 'لجنة السعادة' or d.details->'projects' ? 'لجنة السعادة'
or 'لجنة السعادة'=any(documentation_private.legacy_tag_names(d.committees)) or 'لجنة السعادة'=any(documentation_private.legacy_tag_names(d.projects))
or exists(select 1 from public.documentation_tags l join public.school_tags t on t.id=l.tag_id where l.documentation_id=d.id and t.kind='committee' and t.name='لجنة السعادة')
)) $$;
revoke all on function documentation_private.happiness_reader(bigint) from public,anon;
grant execute on function documentation_private.happiness_reader(bigint) to authenticated;
drop policy happiness_activity_delegate_read on public.documentations;
create policy happiness_read_only_delegate on public.documentations for select to authenticated using(documentation_private.happiness_reader(id));
