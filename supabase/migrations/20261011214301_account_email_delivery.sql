create table public.account_email_deliveries(id uuid primary key,actor_id uuid not null references public.profiles(id),recipient_id uuid not null references public.profiles(id),mode text not null check(mode in('test','teacher')),rate_slot bigint not null,status text not null check(status in('pending','accepted','uncertain')),created_at timestamptz not null default now(),finished_at timestamptz,unique(recipient_id,rate_slot));
alter table public.account_email_deliveries enable row level security;
revoke all on public.account_email_deliveries from anon,authenticated;
grant select on public.account_email_deliveries to authenticated;
grant all on public.account_email_deliveries to service_role;
create policy account_email_admin_read on public.account_email_deliveries for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.school_access='all' and p.role in('principal','assistant_principal')));
create index account_email_delivery_history on public.account_email_deliveries(created_at desc);
