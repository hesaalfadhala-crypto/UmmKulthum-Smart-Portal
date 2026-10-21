-- User-confirmed school catalog; unknown classroom floors remain unassigned.
alter table public.building_locations alter column floor_id drop not null;
alter table public.building_locations add constraint building_unassigned_class_only check(floor_id is not null or type='classroom');
create unique index building_class_identity on public.building_locations(canonical_name) where type='classroom';
insert into public.building_floors(name) values('الأرضي'),('الأول'),('الثاني') on conflict(canonical_name) do nothing;
insert into public.building_locations(type,name,grade,section)
select 'classroom',g.grade||'/'||n::text,g.grade,n::text
from (values('السادس',8),('الأول الإعدادي',6),('الثاني الإعدادي',7),('الثالث الإعدادي',8)) g(grade,total)
cross join lateral generate_series(1,g.total) n
where not exists(select 1 from public.building_locations l where l.type='classroom' and l.canonical_name=building_private.key(g.grade||'/'||n::text));
