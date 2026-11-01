-- Add catalogue choices only; existing reports and permissions remain intact.
insert into public.school_tags(kind,name) values
('committee','لجنة العلاقات العامة'),
('committee','لجنة الزراعة'),
('committee','لجنة النظام'),
('committee','لجنة المرشدات الصحيات')
on conflict(kind,name) do nothing;
