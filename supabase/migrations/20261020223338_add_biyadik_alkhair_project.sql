-- Register the project for the existing documentation tag synchronization and archive filters.
insert into public.school_tags(kind,name)
values ('project','بيدك الخير')
on conflict(kind,name) do nothing;
