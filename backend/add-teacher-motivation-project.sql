-- Independent catalog entry. Existing projects, tags and reports stay intact.
insert into public.school_tags(kind,name)
select 'project','تحفيز المعلمات'
where not exists(select 1 from public.school_tags where kind='project' and name='تحفيز المعلمات');
