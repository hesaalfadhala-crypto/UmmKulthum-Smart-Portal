-- Independent recognition system. No writes to profiles, Auth or documentations.
create schema hasad_private;
revoke all on schema hasad_private from public,anon;
grant usage on schema hasad_private to authenticated;
create table hasad_private.backups(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),source text not null,snapshot jsonb not null);
alter table hasad_private.backups enable row level security;
revoke all on hasad_private.backups from public,anon,authenticated;
insert into hasad_private.backups(source,snapshot) select 'report_admins',coalesce(jsonb_agg(to_jsonb(a)),'[]') from documentation_private.report_admins a;
create table hasad_private.administrators(user_id uuid primary key references public.profiles(id),principal boolean not null default false,can_approve boolean not null default false);
alter table hasad_private.administrators enable row level security;
revoke all on hasad_private.administrators from public,anon,authenticated;
insert into hasad_private.administrators select p.id,p.role='principal',p.role='principal' from documentation_private.report_admins a join public.profiles p on p.id=a.user_id;
create table public.hasad_categories(id text primary key,title text not null,sort_order integer not null);
create table public.hasad_levels(id text primary key,category_id text not null references public.hasad_categories,title text not null,period text,review_note text);
create table public.hasad_criteria(id text primary key,level_id text not null references public.hasad_levels,title text not null,sort_order integer not null);
create table public.hasad_reward_rules(id text primary key,level_id text not null references public.hasad_levels,kind text not null check(kind in('hours','day','certificate','breakfast')),quantity numeric(8,2) not null check(quantity>0),title text not null);
create table public.hasad_members(category_id text not null references public.hasad_categories,user_id uuid not null references public.profiles(id),active boolean not null default true,primary key(category_id,user_id));
create table public.hasad_awards(id uuid primary key,request_id uuid not null unique,last_request_id uuid not null,created_by uuid not null references public.profiles(id),category_id text not null references public.hasad_categories,level_id text not null references public.hasad_levels,title text not null,event_date date not null,period_from date,period_to date,academic_year text not null,semester text not null default '',department text not null default '',is_department boolean not null default false,reason text not null default '',public_summary text not null default '',committee_notes text not null default '',criteria_ids text[] not null default '{}',files jsonb not null default '[]',public_photo jsonb,announce boolean not null default true,status text not null default 'draft' check(status in('draft','pending','approved','returned','cancelled')),review_note text not null default '',approved_by uuid references public.profiles(id),approved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),version integer not null default 1,check(period_to is null or period_from is null or period_to>=period_from));
create table public.hasad_recipients(award_id uuid not null references public.hasad_awards(id),user_id uuid not null references public.profiles(id),full_name text not null,department text not null default '',primary key(award_id,user_id));
create table public.hasad_rewards(id uuid primary key default gen_random_uuid(),award_id uuid not null,user_id uuid not null,rule_id text not null references public.hasad_reward_rules,kind text not null,title text not null,quantity numeric(8,2) not null,state text not null default 'due' check(state in('due','executed','cancelled')),due_on date not null,executed_on date,notes text not null default '',updated_at timestamptz not null default now(),unique(award_id,user_id,rule_id),foreign key(award_id,user_id) references public.hasad_recipients(award_id,user_id),check((state='executed' and executed_on is not null) or state<>'executed'));
-- Safe published projection: deliberately contains no entitlement or discipline columns.
create table public.hasad_public_cards(award_id uuid not null references public.hasad_awards(id),user_id uuid not null references public.profiles(id),full_name text not null,department text not null,category_id text not null,level_id text not null,title text not null,event_date date not null,academic_year text not null,summary text not null,is_department boolean not null,award_department text not null,photo jsonb,primary key(award_id,user_id));
create table public.hasad_notifications(id uuid primary key default gen_random_uuid(),recipient_id uuid not null references public.profiles(id),award_id uuid not null references public.hasad_awards(id),event text not null default 'approved',message text not null,created_at timestamptz not null default now(),read_at timestamptz,unique(recipient_id,award_id,event));
create table hasad_private.audit(id bigint generated always as identity primary key,award_id uuid,actor_id uuid,action text not null,previous jsonb,current_data jsonb,created_at timestamptz not null default now());
alter table hasad_private.audit enable row level security;revoke all on hasad_private.audit from public,anon,authenticated;
create index on public.hasad_awards(created_by,status);create index on public.hasad_awards(event_date,category_id);create index on public.hasad_recipients(user_id);create index on public.hasad_rewards(user_id,state);create index on public.hasad_notifications(recipient_id,created_at);
create function hasad_private.signed_in() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid())$$;
create function hasad_private.admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from hasad_private.administrators where user_id=auth.uid())$$;
create function hasad_private.principal() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from hasad_private.administrators where user_id=auth.uid() and principal)$$;
create function hasad_private.approver() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from hasad_private.administrators where user_id=auth.uid() and can_approve)$$;
create function hasad_private.member(cat text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.hasad_members where user_id=auth.uid() and category_id=cat and active)$$;
create function hasad_private.editor(aid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.hasad_awards a where a.id=aid and (hasad_private.admin() or a.created_by=auth.uid() and hasad_private.member(a.category_id)))$$;
create function hasad_private.recipient(aid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.hasad_recipients r join public.hasad_awards a on a.id=r.award_id where r.award_id=aid and r.user_id=auth.uid() and a.status='approved')$$;
-- Clients cannot write business tables directly, even if a future policy is added.
do $$declare t text;begin
 foreach t in array array['hasad_categories','hasad_levels','hasad_criteria','hasad_reward_rules','hasad_members','hasad_awards','hasad_recipients','hasad_rewards','hasad_public_cards','hasad_notifications'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['hasad_categories','hasad_levels','hasad_criteria','hasad_reward_rules','hasad_public_cards'] loop execute format('create policy authorized_read on public.%I for select to authenticated using(hasad_private.signed_in())',t);end loop;
end$$;
create policy own_membership on public.hasad_members for select to authenticated using(user_id=auth.uid() or hasad_private.admin());
create policy staff_awards on public.hasad_awards for select to authenticated using(hasad_private.admin() or created_by=auth.uid() and hasad_private.member(category_id));
create policy own_recipients on public.hasad_recipients for select to authenticated using(hasad_private.editor(award_id) or user_id=auth.uid() and hasad_private.recipient(award_id));
create policy own_rewards on public.hasad_rewards for select to authenticated using(user_id=auth.uid() or hasad_private.admin());
create policy own_notifications on public.hasad_notifications for select to authenticated using(recipient_id=auth.uid());
create function hasad_private.context() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not hasad_private.signed_in() then raise exception 'يرجى تسجيل الدخول';end if;
 return jsonb_build_object('user_id',auth.uid(),'admin',hasad_private.admin(),'principal',hasad_private.principal(),'can_approve',hasad_private.approver(),'categories',(select coalesce(jsonb_agg(category_id),'[]') from public.hasad_members where user_id=auth.uid() and active),'delegates',case when hasad_private.admin() then (select coalesce(jsonb_agg(jsonb_build_object('id',d.user_id,'name',p.full_name,'can_approve',d.can_approve)),'[]') from hasad_private.administrators d join public.profiles p on p.id=d.user_id where not d.principal) else '[]'::jsonb end,'profile',(select jsonb_build_object('name',full_name,'department',department) from public.profiles where id=auth.uid()));end$$;
create function hasad_private.staff() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not hasad_private.admin() and not exists(select 1 from public.hasad_members where user_id=auth.uid() and active) then raise exception 'غير مصرح' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'department',department,'job_title',job_title) order by full_name),'[]') from public.profiles);end$$;
create function hasad_private.records() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not hasad_private.signed_in() then raise exception 'غير مصرح' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('recipients',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.hasad_recipients r where r.award_id=a.id),'rewards',(case when hasad_private.admin() then (select coalesce(jsonb_agg(to_jsonb(w)),'[]') from public.hasad_rewards w where w.award_id=a.id) else '[]'::jsonb end)) order by a.created_at desc),'[]') from public.hasad_awards a where hasad_private.admin() or a.created_by=auth.uid() and hasad_private.member(a.category_id));end$$;
create function hasad_private.mine() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not hasad_private.signed_in() then raise exception 'غير مصرح';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'category_id',a.category_id,'level_id',a.level_id,'title',a.title,'event_date',a.event_date,'academic_year',a.academic_year,'semester',a.semester,'department',a.department,'reason',case when a.category_id='discipline' then 'استيفاء معايير مستوى الانضباط المعتمد' else a.reason end,'period_from',a.period_from,'period_to',a.period_to,'criteria_ids',a.criteria_ids,'approved_at',a.approved_at,'status',a.status,'files',a.files,'recipients',jsonb_build_array(to_jsonb(r)),'rewards',(select coalesce(jsonb_agg(to_jsonb(w)),'[]') from public.hasad_rewards w where w.award_id=a.id and w.user_id=auth.uid())) order by a.event_date desc),'[]') from public.hasad_awards a join public.hasad_recipients r on r.award_id=a.id where r.user_id=auth.uid() and a.status='approved');end$$;
create function hasad_private.refresh_public(aid uuid) returns void language plpgsql security definer set search_path='' as $$begin
 delete from public.hasad_public_cards where award_id=aid;
 insert into public.hasad_public_cards select a.id,r.user_id,r.full_name,r.department,a.category_id,a.level_id,a.title,a.event_date,a.academic_year,case when a.category_id='discipline' then 'تقديرًا للانضباط الوظيفي واستيفاء معايير التكريم' else a.public_summary end,a.is_department,a.department,a.public_photo from public.hasad_awards a join public.hasad_recipients r on r.award_id=a.id where a.id=aid and a.status='approved' and a.announce;
end$$;
create function hasad_private.save(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.hasad_awards;oldrow public.hasad_awards;aid uuid:=(payload->>'id')::uuid;cat text:=payload->>'category_id';lev text:=payload->>'level_id';uids uuid[];criteria text[];f jsonb;people int;begin
 if not hasad_private.signed_in() or not(hasad_private.admin() or hasad_private.member(cat)) then raise exception 'غير مصرح لهذه الفئة' using errcode='42501';end if;
 select * into oldrow from public.hasad_awards where id=aid for update;
 if oldrow.id is not null and hasad_private.editor(aid) and oldrow.last_request_id=(payload->>'request_id')::uuid then return to_jsonb(oldrow);end if;
 if oldrow.id is not null and (not hasad_private.editor(aid) or (oldrow.status not in('draft','returned','pending') and not hasad_private.admin()) or oldrow.status='cancelled') then raise exception 'لا يمكن تعديل الترشيح في حالته الحالية' using errcode='42501';end if;
 if oldrow.id is not null and oldrow.version<>coalesce((payload->>'version')::int,0) then raise exception 'عُدّل السجل في نافذة أخرى؛ أعيدي فتحه قبل الحفظ';end if;
 if oldrow.id is not null and oldrow.category_id<>cat and not hasad_private.admin() then raise exception 'لا يمكن نقل الترشيح إلى لجنة أخرى';end if;
 if not exists(select 1 from public.hasad_levels where id=lev and category_id=cat) then raise exception 'مستوى غير صالح';end if;
 select coalesce(array_agg(v::uuid),'{}') into uids from jsonb_array_elements_text(payload->'recipients') v;
 people:=cardinality(uids);
 if cat='department' and (not coalesce((payload->>'is_department')::boolean,false) or btrim(coalesce(payload->>'department',''))='') then raise exception 'حددي القسم وعضواته المشمولات بالتكريم';end if;
 if people<1 or people>1000 or people<>(select count(distinct x) from unnest(uids) x) or people<>(select count(*) from public.profiles where id=any(uids)) then raise exception 'راجعي أسماء المكرمات ومنع التكرار';end if;
 select coalesce(array_agg(v),'{}') into criteria from jsonb_array_elements_text(coalesce(payload->'criteria_ids','[]')) v;
 if exists(select 1 from unnest(criteria) x where not exists(select 1 from public.hasad_criteria where id=x and level_id=lev)) then raise exception 'معيار غير صالح';end if;
 if length(btrim(coalesce(payload->>'title',''))) not between 1 and 300 or length(btrim(coalesce(payload->>'academic_year',''))) not between 4 and 30 then raise exception 'أكملي العنوان والعام الدراسي';end if;
 if octet_length(payload::text)>2097152 or length(coalesce(payload->>'reason',''))>20000 or length(coalesce(payload->>'public_summary',''))>500 then raise exception 'البيانات أكبر من الحد المسموح';end if;
 if jsonb_typeof(coalesce(payload->'files','[]'))<>'array' or jsonb_array_length(coalesce(payload->'files','[]'))>15 then raise exception 'الحد الأقصى 15 مرفقًا';end if;
 if (select count(*) from jsonb_array_elements(coalesce(payload->'files','[]')) x where x->>'kind'='photo')>10 or (select count(*) from jsonb_array_elements(coalesce(payload->'files','[]')) x where x->>'kind'='pdf')>5 then raise exception 'الحد الأقصى 10 صور و5 ملفات PDF';end if;
 for f in select value from jsonb_array_elements(coalesce(payload->'files','[]')) loop
  if coalesce(f->>'bucket','')<>'school-hasad-files' or coalesce(f->>'kind','') not in('photo','pdf') or length(coalesce(f->>'name',''))>240 or split_part(f->>'path','/',2)<>aid::text or not exists(select 1 from storage.objects where bucket_id='school-hasad-files' and name=f->>'path' and ((f->>'kind'='photo' and name like '%.jpg' and metadata->>'mimetype'='image/jpeg') or (f->>'kind'='pdf' and name like '%.pdf' and metadata->>'mimetype'='application/pdf'))) or not(coalesce(oldrow.files,'[]') @> jsonb_build_array(f)) and split_part(f->>'path','/',1)<>auth.uid()::text then raise exception 'مرجع مرفق غير صالح';end if;
 end loop;
 if payload->'public_photo' is not null and payload->'public_photo'<>'null'::jsonb and (payload->'public_photo'->>'kind'<>'photo' or not(coalesce(payload->'files','[]') @> jsonb_build_array(payload->'public_photo'))) then raise exception 'صورة الإعلان غير مرتبطة بالتكريم';end if;
 if oldrow.status='approved' and (oldrow.level_id<>lev or oldrow.category_id<>cat or (select array_agg(user_id order by user_id) from public.hasad_recipients where award_id=aid)<>(select array_agg(x order by x) from unnest(uids) x)) then raise exception 'لا يمكن تغيير المستحقة أو المكافأة بعد الاعتماد. ألغِي السجل مع سبب ثم أنشئي ترشيحًا صحيحًا';end if;
 if oldrow.id is null then
 insert into public.hasad_awards(id,request_id,last_request_id,created_by,category_id,level_id,title,event_date,academic_year) values(aid,(payload->>'request_id')::uuid,(payload->>'request_id')::uuid,auth.uid(),cat,lev,payload->>'title',(payload->>'event_date')::date,payload->>'academic_year');
 end if;
 update public.hasad_awards set status=case when oldrow.status='pending' then 'draft' else status end,last_request_id=(payload->>'request_id')::uuid,category_id=cat,level_id=lev,title=payload->>'title',event_date=(payload->>'event_date')::date,period_from=nullif(payload->>'period_from','')::date,period_to=nullif(payload->>'period_to','')::date,academic_year=payload->>'academic_year',semester=coalesce(payload->>'semester',''),department=coalesce(payload->>'department',''),is_department=coalesce((payload->>'is_department')::boolean,false),reason=coalesce(payload->>'reason',''),public_summary=coalesce(payload->>'public_summary',''),committee_notes=coalesce(payload->>'committee_notes',''),criteria_ids=criteria,files=coalesce(payload->'files','[]'),public_photo=nullif(payload->'public_photo','null'::jsonb),announce=coalesce((payload->>'announce')::boolean,true),updated_at=now(),version=case when oldrow.id is null then 1 else oldrow.version+1 end where id=aid returning * into a;
 if a.status<>'approved' then delete from public.hasad_recipients where award_id=aid;insert into public.hasad_recipients select aid,id,full_name,coalesce(department,'') from public.profiles where id=any(uids);end if;
 insert into hasad_private.audit(award_id,actor_id,action,previous,current_data) values(aid,auth.uid(),'save',case when oldrow.id is null then null else to_jsonb(oldrow) end,to_jsonb(a));
 perform hasad_private.refresh_public(aid);return to_jsonb(a);
end$$;
create function hasad_private.transition(aid uuid,expected_version int,action text,note text,verified boolean,announce boolean) returns jsonb language plpgsql security definer set search_path='' as $$declare a public.hasad_awards;prev jsonb;begin
 select * into a from public.hasad_awards where id=aid for update;
 if a.id is null or not hasad_private.editor(aid) then raise exception 'غير مصرح' using errcode='42501';end if;
 if a.version<>expected_version then raise exception 'السجل تغير؛ أعيدي فتحه';end if;prev:=to_jsonb(a);
 if action in('submit','approve') and a.category_id in('discipline','department') and (a.period_from is null or a.period_to is null) then raise exception 'حددي بداية فترة الاستحقاق ونهايتها';end if;
 if action='submit' then
  if a.status not in('draft','returned') or cardinality(a.criteria_ids)=0 or btrim(a.reason)='' then raise exception 'أكملي معيار الاستحقاق وسبب التكريم';end if;
  a.status:='pending';a.review_note:='';
 elsif action='approve' then
  if not hasad_private.approver() then raise exception 'الاعتماد النهائي للمديرة أو المفوضة صراحةً' using errcode='42501';end if;
  if not hasad_private.principal() and exists(select 1 from public.hasad_recipients where award_id=aid and user_id=auth.uid()) then raise exception 'لا يمكن اعتماد مكافأة لنفسكِ';end if;
  if a.status not in('draft','pending','returned') or not verified or cardinality(a.criteria_ids)=0 or btrim(a.reason)='' then raise exception 'راجعي الاستحقاق وأكدي التحقق من المعايير';end if;
  a.status:='approved';a.approved_by:=auth.uid();a.approved_at:=now();a.announce:=announce;
 elsif action='return' then
  if not hasad_private.admin() or a.status<>'pending' or btrim(coalesce(note,''))='' then raise exception 'تتطلب الإعادة ملاحظة الإدارة وطلبًا معلقًا';end if;a.status:='returned';a.review_note:=note;
 elsif action='cancel' then
  if not hasad_private.admin() or a.status='cancelled' or btrim(coalesce(note,''))='' then raise exception 'الإلغاء للإدارة مع ذكر السبب';end if;a.status:='cancelled';a.review_note:=note;
 else raise exception 'إجراء غير صالح';end if;
 update public.hasad_awards set status=a.status,approved_by=a.approved_by,approved_at=a.approved_at,announce=a.announce,review_note=a.review_note,updated_at=now(),version=version+1 where id=aid returning * into a;
 if action='approve' then
 insert into public.hasad_rewards(award_id,user_id,rule_id,kind,title,quantity,due_on) select aid,r.user_id,w.id,w.kind,w.title,w.quantity,a.event_date from public.hasad_recipients r join public.hasad_reward_rules w on w.level_id=a.level_id where r.award_id=aid on conflict(award_id,user_id,rule_id) do nothing;
 insert into public.hasad_notifications(recipient_id,award_id,message) select user_id,aid,'🌷 مبارك لكِ! أشرقت دانة جديدة باسمكِ في حصاد الدانات، تقديرًا لعطائكِ وجهودكِ المتميزة. اضغطي للاطلاع على تكريمكِ.' from public.hasad_recipients where award_id=aid on conflict(recipient_id,award_id,event) do nothing;
 elsif action='cancel' then
 insert into hasad_private.audit(award_id,actor_id,action,previous) select aid,auth.uid(),'cancel_reward',to_jsonb(w) from public.hasad_rewards w where award_id=aid;
 update public.hasad_rewards set state='cancelled',updated_at=now() where award_id=aid;
 end if;
 perform hasad_private.refresh_public(aid);insert into hasad_private.audit(award_id,actor_id,action,previous,current_data) values(aid,auth.uid(),action,prev,to_jsonb(a));return to_jsonb(a);
end$$;
create function hasad_private.reward_update(rid uuid,new_state text,execution_date date,note text) returns void language plpgsql security definer set search_path='' as $$declare w public.hasad_rewards;begin
 if not hasad_private.admin() then raise exception 'غير مصرح' using errcode='42501';end if;
 select * into w from public.hasad_rewards where id=rid for update;if w.id is null or not exists(select 1 from public.hasad_awards where id=w.award_id and status='approved') then raise exception 'استحقاق غير قابل للتنفيذ';end if;
 if new_state not in('due','executed','cancelled') or new_state='executed' and execution_date is null then raise exception 'حددي حالة التنفيذ وتاريخه';end if;
 update public.hasad_rewards set state=new_state,executed_on=case when new_state='executed' then execution_date else null end,notes=coalesce(note,''),updated_at=now() where id=rid;
 insert into hasad_private.audit(award_id,actor_id,action,previous,current_data) values(w.award_id,auth.uid(),'reward',to_jsonb(w),jsonb_build_object('state',new_state,'date',execution_date,'note',note));end$$;
create function hasad_private.read_notification(nid uuid) returns void language plpgsql security definer set search_path='' as $$begin update public.hasad_notifications set read_at=coalesce(read_at,now()) where id=nid and recipient_id=auth.uid();end$$;
create function hasad_private.manage_member(uid uuid,cat text,enabled boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not hasad_private.admin() then raise exception 'غير مصرح' using errcode='42501';end if;
 insert into hasad_private.backups(source,snapshot) select 'members_before_change',coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.hasad_members m;
 insert into public.hasad_members values(cat,uid,enabled) on conflict(category_id,user_id) do update set active=excluded.active;
 insert into hasad_private.audit(actor_id,action,current_data) values(auth.uid(),'membership',jsonb_build_object('user_id',uid,'category',cat,'active',enabled));end$$;
create function hasad_private.delegate(uid uuid,enabled boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not hasad_private.principal() then raise exception 'التفويض من المديرة فقط' using errcode='42501';end if;
 if not exists(select 1 from hasad_private.administrators where user_id=uid and not principal) then raise exception 'المفوضة ليست إدارية في حصاد الدانات';end if;
 insert into hasad_private.backups(source,snapshot) select 'administrators_before_delegation',jsonb_agg(to_jsonb(a)) from hasad_private.administrators a;
 update hasad_private.administrators set can_approve=enabled where user_id=uid and not principal;
 insert into hasad_private.audit(actor_id,action,current_data) values(auth.uid(),'delegation',jsonb_build_object('user_id',uid,'active',enabled));end$$;
-- Only approved photo projections can be viewed by other signed-in staff.
create function hasad_private.file_read(path text) returns boolean language sql stable security definer set search_path='' as $$select hasad_private.signed_in() and (exists(select 1 from public.hasad_awards a where a.files @> jsonb_build_array(jsonb_build_object('bucket','school-hasad-files','path',path)) and (hasad_private.editor(a.id) or hasad_private.recipient(a.id))) or exists(select 1 from public.hasad_public_cards c where c.photo->>'path'=path))$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('school-hasad-files','school-hasad-files',false,8388608,array['image/jpeg','application/pdf']);
create policy hasad_evidence_insert on storage.objects for insert to authenticated with check(bucket_id='school-hasad-files' and hasad_private.signed_in() and (hasad_private.admin() or exists(select 1 from public.hasad_members where user_id=auth.uid() and active)) and split_part(name,'/',1)=auth.uid()::text and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|pdf)$' and ((name like '%.jpg' and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint<=3145728) or (name like '%.pdf' and metadata->>'mimetype'='application/pdf' and (metadata->>'size')::bigint<=8388608)));
create policy hasad_evidence_read on storage.objects for select to authenticated using(bucket_id='school-hasad-files' and hasad_private.file_read(name));
-- All privileged implementations live in the unexposed schema. Wrappers use INVOKER.
create function public.hasad_context() returns jsonb language sql stable security invoker set search_path='' as $$select hasad_private.context()$$;
create function public.hasad_staff() returns jsonb language sql stable security invoker set search_path='' as $$select hasad_private.staff()$$;
create function public.hasad_records() returns jsonb language sql stable security invoker set search_path='' as $$select hasad_private.records()$$;
create function public.hasad_mine() returns jsonb language sql stable security invoker set search_path='' as $$select hasad_private.mine()$$;
create function public.hasad_save(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select hasad_private.save(payload)$$;
create function public.hasad_action(aid uuid,expected_version int,action text,note text default '',verified boolean default false,announce boolean default true) returns jsonb language sql security invoker set search_path='' as $$select hasad_private.transition(aid,expected_version,action,note,verified,announce)$$;
create function public.hasad_reward_update(rid uuid,new_state text,execution_date date default null,note text default '') returns void language sql security invoker set search_path='' as $$select hasad_private.reward_update(rid,new_state,execution_date,note)$$;
create function public.hasad_read_notification(nid uuid) returns void language sql security invoker set search_path='' as $$select hasad_private.read_notification(nid)$$;
create function public.hasad_manage_member(uid uuid,cat text,enabled boolean) returns void language sql security invoker set search_path='' as $$select hasad_private.manage_member(uid,cat,enabled)$$;
create function public.hasad_delegate(uid uuid,enabled boolean) returns void language sql security invoker set search_path='' as $$select hasad_private.delegate(uid,enabled)$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='hasad_private' or n.nspname='public' and p.proname like 'hasad_%' loop execute format('revoke all on function %s from public,anon,authenticated',f.sig);if f.sig::text not like '%refresh_public%' then execute format('grant execute on function %s to authenticated',f.sig);end if;end loop;
end$$;

insert into public.hasad_categories(id,title,sort_order) values
('discipline','ملكات الانضباط',1),
('department','القسم المتميز',2),
('stars','نجوم لامعة',3),
('digital','بصمات رقمية',4),
('inspiration','دانات الإلهام والتحدي',5);

insert into public.hasad_levels(id,category_id,title,period,review_note) values
('discipline-gold','discipline','البوبيل الذهبي','شهر',''),
('discipline-silver','discipline','البوبيل الفضي','شهر','شرط «غياب 1 أو استئذان 1 أو تأخير 1» يحتاج تفسيرًا معتمدًا. لا يتحقق النظام من الاستحقاق تلقائيًا؛ يلزم تحقق المديرة.'),
('discipline-vip','discipline','VIP','فصل',''),
('department-distinguished','department','القسم المتميز','شهر',''),
('stars-gold','stars','نجوم لامعة ذهبية','فصل',''),
('stars-silver','stars','نجوم لامعة فضية','',''),
('digital-distinguished','digital','بصمات رقمية','',''),
('inspiration-distinguished','inspiration','دانات الإلهام والتحدي','فصل','');

insert into public.hasad_criteria(id,level_id,title,sort_order) values
('discipline-gold-1','discipline-gold','طوال الشهر: غياب 0، استئذان 0، تأخير 0.',1),
('discipline-silver-1','discipline-silver','طوال الشهر: غياب 1 أو استئذان 1 أو تأخير 1.',1),
('discipline-vip-1','discipline-vip','طوال الفصل: غياب 0، استئذان 0، تأخير 0.',1),
('department-distinguished-1','department-distinguished','الانضباط الوظيفي لجميع منتسبات القسم لمدة شهر كامل.',1),
('department-distinguished-2','department-distinguished','المهنية في العمل وأداء ما يوكل إليهن من مهام على أكمل وجه.',2),
('department-distinguished-3','department-distinguished','المبادرة والتعاون مع جميع أقسام المدرسة.',3),
('department-distinguished-4','department-distinguished','التميز في تفعيل الأسابيع الثقافية.',4),
('department-distinguished-5','department-distinguished','إعداد فعاليات وبرامج تعزز من الشراكة المجتمعية.',5),
('stars-gold-1','stars-gold','الحصول على تقدير يتجاوز التوقعات بكثير في المواقف التعليمية.',1),
('stars-gold-2','stars-gold','التميز في الأعمال الكتابية وتميز الاحتفاء بها في الصفوف.',2),
('stars-gold-3','stars-gold','حصول صفوف المعلمة على أعلى نسبة إتقان.',3),
('stars-gold-4','stars-gold','المبادرة في تقديم أكثر من ورشتين ضمن مركز الدعم والتطوير المهني خلال الفصل.',4),
('stars-gold-5','stars-gold','الحصول على لقب التوأم الذهبي ضمن مركز الدعم والتطوير المهني.',5),
('stars-silver-1','stars-silver','الحصول على تقدير يتجاوز التوقعات في المواقف التعليمية.',1),
('stars-silver-2','stars-silver','المبادرة في تقديم ورشة على الأقل ضمن مركز الدعم والتطوير المهني.',2),
('digital-distinguished-1','digital-distinguished','تقديم ممارسة متميزة في التمكين الرقمي.',1),
('digital-distinguished-2','digital-distinguished','المبادرة في تقديم ورش ضمن فريق التمكين الرقمي.',2),
('digital-distinguished-3','digital-distinguished','حصول المعلمة على شهادة المعلم الخبير.',3),
('digital-distinguished-4','digital-distinguished','المساهمة في حصول المدرسة على لقب المدرسة الحاضنة للتكنولوجيا.',4),
('digital-distinguished-5','digital-distinguished','الترشح لتحقيق أعلى نسبة مشاركة شهريًا في تفعيل بوابة أم كلثوم الذكية.',5),
('digital-distinguished-6','digital-distinguished','تقديم دروس نموذجية عند زيارات الوفود وإدارة سياسات التعليم.',6),
('inspiration-distinguished-1','inspiration-distinguished','المشاركة في عمل تطوعي متميز.',1),
('inspiration-distinguished-2','inspiration-distinguished','أداء عمل متميز أو حصاد مركز على مستوى وزاري.',2),
('inspiration-distinguished-3','inspiration-distinguished','تحقيق قصة نجاح خلال الفصل الدراسي.',3),
('inspiration-distinguished-4','inspiration-distinguished','تقديم بحث إجرائي متميز.',4),
('inspiration-distinguished-5','inspiration-distinguished','تقديم مقترح لتحسين وتبسيط إجراءات العمل بما يوفر الوقت والجهد والميزانية.',5);

insert into public.hasad_reward_rules(id,level_id,kind,quantity,title) values
('discipline-gold-hours','discipline-gold','hours',3,'3 ساعات سعادة'),
('discipline-silver-hours','discipline-silver','hours',2,'ساعتان سعادة'),
('discipline-vip-day','discipline-vip','day',1,'يوم تعويضي'),
('department-distinguished-certificate','department-distinguished','certificate',1,'شهادة القسم المتميز'),
('department-distinguished-breakfast','department-distinguished','breakfast',1,'فطور جماعي للقسم'),
('stars-gold-certificate','stars-gold','certificate',1,'شهادات شكر'),
('stars-gold-hours','stars-gold','hours',3,'3 ساعات سعادة'),
('stars-silver-certificate','stars-silver','certificate',1,'شهادات شكر'),
('stars-silver-hours','stars-silver','hours',2,'ساعتان سعادة'),
('digital-distinguished-hours','digital-distinguished','hours',3,'3 ساعات سعادة'),
('inspiration-distinguished-certificate','inspiration-distinguished','certificate',1,'شهادات شكر'),
('inspiration-distinguished-day','inspiration-distinguished','day',1,'يوم تعويضي');

insert into hasad_private.backups(source,snapshot) select 'profiles_reference_before_activation',coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.profiles p;
