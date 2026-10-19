-- Display data is independent of authorization roles. No existing policy/grant is expanded.
create schema staff_private;
revoke all on schema staff_private from public,anon,authenticated;
create table staff_private.backup_runs(id uuid primary key,created_at timestamptz not null default now(),source_digest text not null,baseline jsonb not null);
create table staff_private.backup_rows(batch_id uuid references staff_private.backup_runs(id),table_name text not null,row_id text not null,data jsonb not null,primary key(batch_id,table_name,row_id));
alter table staff_private.backup_runs enable row level security;alter table staff_private.backup_rows enable row level security;
revoke all on all tables in schema staff_private from public,anon,authenticated;
alter table public.profiles add column job_title text,add column departments text[] not null default '{}';
alter table public.observation_teachers add column job_title text,add column departments text[] not null default '{}';
-- A genuinely blank department is valid display data for administrative staff.
alter table public.weekly_staff drop constraint weekly_staff_department_check;
alter table public.weekly_staff add constraint weekly_staff_department_check check(length(department)<=100);
create or replace function account_email_private.recipients() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform account_email_private.context();return(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'job_title',p.job_title,'department',coalesce(p.department,''),'role',p.role,'email',u.email) order by p.full_name,p.id),'[]') from public.profiles p join auth.users u on u.id=p.id where p.role in('teacher','first_teacher','coordinator','assistant_principal','principal') and u.email_confirmed_at is not null and lower(u.email) like '%@moe.bh' and(u.banned_until is null or u.banned_until<=now()));end$$;
create or replace function weekly_private.accounts() returns jsonb language plpgsql security definer set search_path='' as $$
begin if not weekly_private.full_access() then raise exception 'قائمة ربط الحسابات للإدارة المخولة فقط.' using errcode='42501';end if;return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'job_title',p.job_title,'department',p.department,'email',u.email,'role',p.role) order by p.full_name) from public.profiles p join auth.users u on u.id=p.id where u.email_confirmed_at is not null),'[]');end$$;
