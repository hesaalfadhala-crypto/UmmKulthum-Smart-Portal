create schema account_email_private;
revoke all on schema account_email_private from public,anon;
grant usage on schema account_email_private to authenticated;
create table public.account_email_batches(
 id uuid primary key,approved_by uuid not null references public.profiles(id),
 test_delivery_id uuid not null references public.account_email_deliveries(id),
 recipient_ids uuid[] not null check(cardinality(recipient_ids) between 1 and 200),
 template_version text not null check(template_version='welcome_20261013'),
 receipt_confirmed_at timestamptz not null,approved_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '24 hours'
);
alter table public.account_email_batches enable row level security;
revoke all on public.account_email_batches from public,anon,authenticated;
grant select on public.account_email_batches to authenticated;grant all on public.account_email_batches to service_role;
create policy account_email_batches_admin_read on public.account_email_batches for select to authenticated using((select documentation_private.can_manage()));
alter table public.account_email_deliveries add column template_version text,add column recipient_email text,add column batch_id uuid references public.account_email_batches(id),add column request_snapshot jsonb not null default '{}';
create unique index account_email_deliveries_one_per_batch on public.account_email_deliveries(batch_id,recipient_id) where batch_id is not null;
create index account_email_deliveries_batch on public.account_email_deliveries(batch_id,recipient_id);
create function account_email_private.context() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin if not documentation_private.can_manage() then raise exception 'إدارة البريد متاحة للمديرة وحصه فقط.' using errcode='42501';end if;return jsonb_build_object('manager',true,'template_version','welcome_20261013');end$$;
create function account_email_private.recipients() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform account_email_private.context();return(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'department',coalesce(p.department,''),'role',p.role,'email',u.email) order by p.full_name,p.id),'[]') from public.profiles p join auth.users u on u.id=p.id where p.role in('teacher','first_teacher','coordinator','assistant_principal','principal') and u.email_confirmed_at is not null and lower(u.email) like '%@moe.bh' and(u.banned_until is null or u.banned_until<=now()));end$$;
create function account_email_private.approve(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare bid uuid:=(payload->>'id')::uuid;tid uuid:=(payload->>'test_delivery_id')::uuid;ids uuid[];r jsonb;prior public.account_email_batches;
begin
 perform account_email_private.context();
 if bid is null or tid is null or payload->'receipt_confirmed' is distinct from 'true'::jsonb or payload->'explicit_approval' is distinct from 'true'::jsonb or jsonb_typeof(payload->'recipient_ids') is distinct from 'array' or jsonb_array_length(payload->'recipient_ids') not between 1 and 200 then raise exception 'يلزم تأكيد وصول الاختبار وموافقة صريحة على المستلمات المحددات.';end if;
 select array_agg(distinct v::uuid order by v::uuid) into ids from jsonb_array_elements_text(payload->'recipient_ids') v;
 if cardinality(ids)<>jsonb_array_length(payload->'recipient_ids') then raise exception 'المستلمات مكررات.';end if;
 perform pg_advisory_xact_lock(hashtextextended(bid::text,0));select * into prior from public.account_email_batches where id=bid;
 if found then if prior.approved_by<>auth.uid() or prior.test_delivery_id<>tid or prior.recipient_ids<>ids then raise exception 'معرف الدفعة مستخدم لطلب آخر.';end if;return jsonb_build_object('id',bid,'count',cardinality(ids),'recovered',true);end if;
 if not exists(select 1 from public.account_email_deliveries where id=tid and mode='test' and status='accepted' and template_version='welcome_20261013' and created_at>now()-interval '24 hours') then raise exception 'ابدئي برسالة اختبار للنص الحالي، ثم أكدي وصولها.';end if;
 r:=account_email_private.recipients();if exists(select 1 from unnest(ids) uid where not exists(select 1 from jsonb_array_elements(r) candidate where (candidate->>'id')::uuid=uid)) then raise exception 'تغيرت قائمة الحسابات الوزارية؛ أعيدي تحميل المستلمات.';end if;
 insert into public.account_email_batches(id,approved_by,test_delivery_id,recipient_ids,template_version,receipt_confirmed_at) values(bid,auth.uid(),tid,ids,'welcome_20261013',now());
 return jsonb_build_object('id',bid,'count',cardinality(ids),'recovered',false);
end$$;
create function public.account_email_context() returns jsonb language sql stable security invoker set search_path='' as $$select account_email_private.context()$$;
create function public.account_email_recipients() returns jsonb language sql stable security invoker set search_path='' as $$select account_email_private.recipients()$$;
create function public.approve_account_email_batch(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select account_email_private.approve(payload)$$;
revoke all on all functions in schema account_email_private from public,anon,authenticated;
grant execute on all functions in schema account_email_private to authenticated;
revoke all on function public.account_email_context(),public.account_email_recipients(),public.approve_account_email_batch(jsonb) from public,anon;
grant execute on function public.account_email_context(),public.account_email_recipients(),public.approve_account_email_batch(jsonb) to authenticated;
