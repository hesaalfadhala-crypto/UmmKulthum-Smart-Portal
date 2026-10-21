-- Change calculation only: no UPDATE/DELETE of reports, reviews, profiles, files or permissions.
-- Legacy Save-to-archive never set status; browser drafts lived in IndexedDB, not this table.
create table achievement_private.minimum_rules_backup(
 id integer primary key check(id=1),captured_at timestamptz not null default now(),view_definition text not null,
 counted_ids jsonb not null,report_hash text,review_hash text
);
alter table achievement_private.minimum_rules_backup enable row level security;
revoke all on achievement_private.minimum_rules_backup from public,anon,authenticated;
insert into achievement_private.minimum_rules_backup(id,view_definition,counted_ids,report_hash,review_hash)
select 1,pg_get_viewdef('achievement_private.candidates'::regclass,true),
 (select coalesce(jsonb_agg(id order by id),'[]') from
 (select c.id,row_number() over(partition by c.fingerprint order by c.id) rn
 from achievement_private.candidates c join public.profiles p on p.id=c.created_by
 where c.complete and not c.test_record and c.deleted_at is null and c.review_state is distinct from 'excluded'
 and c.activity_date<=(now() at time zone 'Asia/Bahrain')::date) x where rn=1),
 (select md5(coalesce(string_agg(to_jsonb(d)::text,'|' order by d.id),'')) from public.documentations d),
 (select md5(coalesce(string_agg(to_jsonb(r)::text,'|' order by r.report_id),'')) from achievement_private.reviews r);
create table achievement_private.legacy_saved_reports(
 report_id bigint primary key references public.documentations(id),owner_id uuid not null references public.profiles(id),saved_at timestamptz not null,
 evidence text not null check(evidence in('archive_submission','legacy_pre_submission'))
);
alter table achievement_private.legacy_saved_reports enable row level security;
revoke all on achievement_private.legacy_saved_reports from public,anon,authenticated;
-- Freeze only already-saved archive rows. Future draft rows cannot opt into this compatibility list.
-- request_id is written only by the completed Save-to-archive path; old pre-request reports
-- qualify only when the previous candidate rule already marked them complete.
insert into achievement_private.legacy_saved_reports(report_id,owner_id,saved_at,evidence)
select d.id,d.created_by,d.created_at,case when d.request_id is not null then 'archive_submission' else 'legacy_pre_submission' end
from public.documentations d join achievement_private.candidates c on c.id=d.id join public.profiles p on p.id=d.created_by
where d.status='draft' and (d.request_id is not null or c.complete)
and coalesce(d.details->>'is_draft','false')<>'true' and coalesce(d.details->>'isDraft','false')<>'true'
and coalesce(d.details->>'status','') not in('draft','مسودة') and coalesce(d.details->>'state','') not in('draft','مسودة')
and coalesce(d.details->>'published','true')<>'false';
create or replace view achievement_private.candidates as
select d.id,d.created_by,coalesce(d.activity_date,(d.created_at at time zone 'Asia/Bahrain')::date) as activity_date,d.edit_version,d.deleted_at,
 coalesce(nullif(btrim(d.activity_type),''),nullif(d.details->>'type',''),'غير محدد') as kind,
 coalesce(nullif(btrim(case when d.department='أخرى' then coalesce(d.details#>>'{otherDetails,department}',d.details->>'departmentOther') else d.department end),''),'غير محدد') as department,
 coalesce(nullif(d.academic_year,''),case when extract(month from coalesce(d.activity_date,(d.created_at at time zone 'Asia/Bahrain')::date))>=9 then extract(year from coalesce(d.activity_date,(d.created_at at time zone 'Asia/Bahrain')::date))::int||'-'||(extract(year from coalesce(d.activity_date,(d.created_at at time zone 'Asia/Bahrain')::date))::int+1) else (extract(year from coalesce(d.activity_date,(d.created_at at time zone 'Asia/Bahrain')::date))::int-1)||'-'||extract(year from coalesce(d.activity_date,(d.created_at at time zone 'Asia/Bahrain')::date))::int end) as academic_year,
 d.semester,
 (nullif(btrim(d.activity),'') is not null
 and coalesce(nullif(btrim(d.activity_type),''),nullif(btrim(d.details->>'type'),'')) is not null
 and exists(select 1 from public.profiles p where p.id=d.created_by and nullif(btrim(p.full_name),'') is not null)
 and (d.status in('published','final','approved') or
 (d.status='draft' and exists(select 1 from achievement_private.legacy_saved_reports s where s.report_id=d.id and s.owner_id=d.created_by and s.saved_at=d.created_at)))
 and coalesce(d.details->>'is_draft','false')<>'true'
 and coalesce(d.details->>'isDraft','false')<>'true'
 and coalesce(d.details->>'status','') not in('draft','مسودة')
 and coalesce(d.details->>'state','') not in('draft','مسودة')
 and coalesce(d.details->>'published','true')<>'false') as complete,
 (d.details ? 'qa_marker' or coalesce(d.details->>'is_test','false')='true' or coalesce(d.details->>'isTest','false')='true'
 or coalesce(d.details->>'is_duplicate','false')='true'
 or coalesce(d.activity,'') ~* '(تجريب|اختبار تقني|اختبار آلي|\mQA\M|\mtest\M|\mdemo\M)') as test_record,
 md5(jsonb_build_array(d.created_by,d.activity_date,lower(regexp_replace(btrim(d.activity),'\s+',' ','g')),d.activity_type,
 regexp_replace(btrim(coalesce(d.goal,'')),'\s+',' ','g'),regexp_replace(btrim(coalesce(d.implementation,'')),'\s+',' ','g'),regexp_replace(btrim(coalesce(d.results,'')),'\s+',' ','g'))::text) as fingerprint,
 r.state as review_state,r.report_version as reviewed_version
from public.documentations d left join achievement_private.reviews r on r.report_id=d.id;

revoke all on achievement_private.candidates from public,anon,authenticated;
