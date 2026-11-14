import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {proposal,matchPerson,validateProposal,sameVisit,MAX_PDF_BYTES} from '../../assets/js/visit-import-model.js';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
test('review model leaves uncertain names, missing grades and dates unresolved',()=>{
 const context={teachers:[{id:id(3),full_name:'إيمان عبدالرضا حبيب',academic_year:'2026-2027'}],observers:[{id:id(2),full_name:'حصه سند الفضاله'}]};
 assert.equal(matchPerson('إيمان عبدالرضا',context.teachers),'');assert.equal(matchPerson('ايمان عبدالرضا حبيب',context.teachers),id(3));
 const item=proposal({teacher_name:'إيمان عبدالرضا حبيب',observer_name:'حصة سند الفضالة',pages:[1,2],ratings:[{criterion_id:1,level:4}],final_judgment:null},4,context);
 assert.deepEqual(item.pages,[5,6]);assert.equal(item.payload.observer_id,id(2));assert.equal(item.ratings[1].level,null);assert.equal(item.payload.visit_date,'');assert.equal(item.details.final_judgment,'');assert.equal(item.reviewed,false);assert.ok(validateProposal(item).length>=5);assert.equal(MAX_PDF_BYTES,52428800);
 assert.equal(sameVisit({teacher_id:'a',observer_id:'a',visit_date:'2026-10-10',lesson_title:'المجموعات'},{teacher_id:'a',observer_id:'b',visit_date:'2026-10-10',lesson_title:'المجموعات'}),false);
});
test('actual Postgres import authorization, source audit, duplicate recovery and observer attribution',async(t)=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;create table profiles(id uuid primary key references auth.users(id),full_name text,role text,department text,school_access text default 'own');create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;`);
 await db.exec(await fs.readFile(new URL('../../supabase/migrations/20261011000936_classroom_observations.sql',import.meta.url),'utf8'));
 await db.exec(await fs.readFile(new URL('../../backend/classroom_pdf_import.sql',import.meta.url),'utf8'));
 for(let i=1;i<=5;i++)await db.query('insert into auth.users values($1)',[id(i)]);
 await db.query("insert into profiles(id,full_name,role,school_access) values($1,'مديرة اختبار','principal','all'),($2,'منسقة اختبار','coordinator','own'),($3,'معلمة اختبار','teacher','own'),($4,'مساعدة اختبار','assistant_principal','all'),($5,'منسقة أخرى','coordinator','own')",[id(1),id(2),id(3),id(4),id(5)]);
 await db.query("insert into observation_teachers(id,user_id,full_name,department,academic_year) values($1,$2,'رياضيات اختبار','الرياضيات','2026-2027'),($3,null,'عربية اختبار','العربية','2026-2027')",[id(101),id(3),id(102)]);
 await db.query("insert into observation_access values($1,'الرياضيات','{}',true),($2,'الرياضيات','{}',true)",[id(2),id(5)]);
 const as=async n=>db.exec(`reset role;set request.jwt.claim.sub='${id(n)}';set role authenticated`);
 const call=async(p={},reviewed=true,b=id(201),pages=[1,2],level=3)=> (await db.query('select public.commit_classroom_pdf_visit($1,$2,$3::jsonb,$4::jsonb,$5::jsonb,$6) result',[b,pages,{teacher_id:id(101),observer_id:id(1),visit_date:'2026-10-20',academic_year:'2026-2027',semester:1,visit_type:'زيارة صفية',lesson_title:'المجموعات',class_section:'أول إعدادي/4',lesson_period:'3',status:'final',...p},Array.from({length:18},(_,i)=>({criterion_id:i+1,level:i===2?level:3})),{final_judgment:3,judgment_basis:'مطابق للأصل بعد المراجعة',skills:[],skills_assessed:false,student_work:[],work_assessed:false,support:[]},reviewed])).rows[0].result;
 const batch=async(n,hash='a')=>db.query('insert into classroom_import_batches(id,file_name,storage_path,source_hash,page_count) values($1,$2,$3,$4,4)',[id(n),'test.pdf',`${id(2)}/${id(n)}.pdf`,hash.repeat(64)]);
 await as(3);await assert.rejects(db.query('select classroom_import_context()'),/صلاحية/);await assert.rejects(batch(201));
 await as(2);const ctx=(await db.query('select classroom_import_context() c')).rows[0].c;assert.equal(ctx.teachers.length,1);assert.equal(ctx.teachers[0].department,'الرياضيات');await batch(201);
 await t.test('private PDF storage and proposals stay within importing account',async()=>{
  await db.query("insert into storage.objects(bucket_id,name) values('classroom-visit-imports',$1)",[`${id(2)}/${id(201)}.pdf`]);
  await as(5);assert.equal((await db.query('select * from classroom_import_batches')).rows.length,0);assert.equal((await db.query('select * from storage.objects')).rows.length,0);await assert.rejects(call(),/ملف غير متاح/);await as(2);
  await assert.rejects(db.query('update classroom_import_batches set extraction_calls=0'),/permission denied/);
 });
 await t.test('review required, complete ratings required, unauthorized department rejected',async()=>{
  await assert.rejects(call({},false),/راجعي/);await assert.rejects(call({},true,id(201),[1,2],null),/الثمانية/);await assert.rejects(call({teacher_id:id(102)}),/القسم/);await assert.rejects(call({observer_id:id(3)}),/الزائرة/);await assert.rejects(call({},true,id(201),[9]),/صفحة/);
 });
 const first=await call();assert.ok(first.id);assert.equal(first.duplicate,false);
 await t.test('original observer is preserved; importer audit records the coordinator',async()=>{
  await db.exec('reset role');const v=(await db.query('select observer_id,observer_name from classroom_visits where id=$1',[first.id])).rows[0];assert.equal(v.observer_id,id(1));assert.equal(v.observer_name,'مديرة اختبار');const r=(await db.query('select * from classroom_import_records where visit_id=$1',[first.id])).rows[0];assert.equal(r.imported_by,id(2));assert.deepEqual(r.source_pages,[1,2]);await as(2);
 });
 await t.test('retry / renamed file / second observer / near duplicate',async()=>{
  const retry=await call();assert.equal(retry.id,first.id);assert.equal(retry.duplicate,true);
  await batch(202,'b');const renamed=await call({},true,id(202));assert.equal(renamed.id,first.id);assert.equal(renamed.duplicate,true);
  const other=await call({observer_id:id(4)});assert.notEqual(other.id,first.id);assert.equal(other.duplicate,false);
  const near=await call({lesson_title:'المجموعات مع اختلاف كتابة'},true,id(202),[3,4]);assert.equal(near.possible_duplicate,true);
  await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from classroom_visits')).rows[0].n,2);await as(2);
 });
 await t.test('existing reports and analysis include imported final visits',async()=>{
  const report=(await db.query("select analyze_classroom_visits('{\"scope\":\"department\",\"department\":\"الرياضيات\",\"academic_year\":\"2026-2027\"}') data")).rows[0].data;
  assert.equal(report.visits.length,2);assert.equal(report.ratings.length,36);
 });
 await t.test('server extraction quota is atomic and bounded',async()=>{for(let i=0;i<60;i++)await db.query('select claim_classroom_pdf_extraction($1)',[id(201)]);await assert.rejects(db.query('select claim_classroom_pdf_extraction($1)',[id(201)]),/محاولات/);});
 }finally{await db.close();}
});
