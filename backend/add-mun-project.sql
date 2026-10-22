-- Add the MUN project to existing documentation tags and archive filtering.
insert into public.school_tags(kind,name)
values ('project','MUN')
on conflict(kind,name) do nothing;
