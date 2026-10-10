-- Run with execute_sql; all fixtures and changes are rolled back.
begin;
select set_config('qa.fixture_user',gen_random_uuid()::text,true);
insert into auth.users(id,email,aud,role) values(current_setting('qa.fixture_user')::uuid,'qa-final-20261011@example.invalid','authenticated','authenticated');
insert into public.profiles(id,full_name,role,department) values(current_setting('qa.fixture_user')::uuid,'QA_ONLY_ROLLBACK','teacher','الرياضيات');
insert into public.documentations(created_by,activity,details) values(current_setting('qa.fixture_user')::uuid,'QA_ONLY_ROLLBACK','{}'::jsonb);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.fixture_user'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.documentations)<>1 then raise exception 'Teacher must see exactly her fixture';end if;
 if exists(select 1 from public.documentations where created_by<>auth.uid()) then raise exception 'Other users data exposed';end if;
 if exists(select 1 from public.forms where created_by<>auth.uid()) then raise exception 'Other drafts exposed';end if;
 if exists(select 1 from public.competitions where created_by<>auth.uid()) then raise exception 'Other competitions exposed';end if;
 begin update public.profiles set role='principal' where id=auth.uid();raise exception 'Role escalation allowed';exception when insufficient_privilege then null;end;
 begin update public.profiles set department='العلوم' where id=auth.uid();raise exception 'Department escalation allowed';exception when insufficient_privilege then null;end;
 begin update public.profiles set school_access='all' where id=auth.uid();raise exception 'Scope escalation allowed';exception when insufficient_privilege then null;end;
 if exists(select 1 from storage.objects where bucket_id='school-documentation-images') then raise exception 'Other users images exposed';end if;
end $$;
reset role;
-- First teacher, coordinator, and a limited assistant retain the same owner boundary.
update public.profiles set role='first_teacher' where id=current_setting('qa.fixture_user')::uuid;
set local role authenticated;
do $$ begin if (select count(*) from public.documentations)<>1 then raise exception 'First teacher boundary failed';end if;end $$;
reset role;
update public.profiles set role='coordinator' where id=current_setting('qa.fixture_user')::uuid;
set local role authenticated;
do $$ begin if (select count(*) from public.documentations)<>1 then raise exception 'Coordinator boundary failed';end if;end $$;
reset role;
update public.profiles set role='assistant_principal' where id=current_setting('qa.fixture_user')::uuid;
set local role authenticated;
do $$ begin if (select count(*) from public.documentations)<>1 then raise exception 'Limited assistant boundary failed';end if;end $$;
reset role;
-- Existing leadership profiles have the explicitly approved school scope.
select set_config('qa.expected_total',(select count(*)::text from public.documentations),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from public.profiles where full_name='هيا محمد النعيمي' and role='principal'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if (select count(*) from public.documentations)<>current_setting('qa.expected_total')::int then raise exception 'Principal school visibility failed';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from public.profiles where full_name='حصه سند الفضاله' and role='assistant_principal'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if (select count(*) from public.documentations)<>current_setting('qa.expected_total')::int then raise exception 'Hessa school visibility failed';end if;end $$;
reset role;
select set_config('request.jwt.claims','{}',true);
set local role anon;
do $$ begin if exists(select 1 from public.documentations) then raise exception 'Anonymous data exposed';end if;end $$;
reset role;
rollback;
select 'PASS: owner isolation, private photos, role/department/scope escalation blocked, principal and authorized assistant school scope, anonymous isolation; fixtures rolled back' as result;
