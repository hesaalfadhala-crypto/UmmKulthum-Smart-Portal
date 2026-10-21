import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {database,as,admin,id,rpc} from '../complete/fixture.mjs';import {databaseRecord,saveSubmission} from '../../assets/js/save-documentation.js';
const file='supabase/migrations/20261021074811_achievement_minimum_saved_requirements.sql';
test('minimum published requirements: legacy archive, no optional fields/images/date, drafts, tests, exclusions, edits, duplicates and privacy',async()=>{
 const db=await database();try{
 await db.exec("alter table profiles add column job_title text,add column departments text[] not null default '{}';alter table documentations add column edit_version integer not null default 0,add column status text default 'draft';");
 for(const f of ['20261019213251_achievement_board.sql','20261019215640_achievement_automatic_counts.sql','20261020060816_achievement_scoped_statistics.sql'])await db.exec(await fs.readFile('supabase/migrations/'+f,'utf8'));
 const today=(await db.query("select (now() at time zone 'Asia/Bahrain')::date::text d")).rows[0].d,year=Number(today.slice(0,4))-(Number(today.slice(5,7))<9?1:0);
 const add=async(n,title,opts={})=>db.query("insert into documentations(id,created_by,activity,activity_type,activity_date,request_id,status,details) values($1,$2,$3,$4,$5,$6,$7,$8)",[n,id(opts.owner||3),title,opts.kind===undefined?'فعالية':opts.kind,opts.noDate?null:today,id(n),opts.status||'draft',opts.details||{}]);
 await add(9201,'فعالية وردية محفوظة');await add(9202,'تقرير باق مستبعد');await add(9203,'مسودة صريحة',{details:{is_draft:true}});await add(9204,'عنوان محفوظ',{kind:''});await add(9205,' ');await add(9206,'تقرير تجريبي');
 await db.query("insert into achievement_private.reviews values(9202,'excluded',0,'قرار استبعاد سابق',$1,now())",[id(1)]);
 const reports=JSON.stringify((await db.query('select * from documentations order by id')).rows),reviews=JSON.stringify((await db.query('select * from achievement_private.reviews')).rows);
 await db.exec(await fs.readFile(file,'utf8'));
 assert.equal(JSON.stringify((await db.query('select * from documentations order by id')).rows),reports);assert.equal(JSON.stringify((await db.query('select * from achievement_private.reviews')).rows),reviews);
 const dash=()=>rpc(db,'achievement_dashboard',{period:'year',year_start:year,department_filter:'',kind_filter:'',project_filter:''});
 await as(db,3);let d=await dash();assert.equal(d.own_total,1);assert.equal(d.totals.reports,1);assert.equal(d.supervision,null);await assert.rejects(db.query('select * from achievement_private.legacy_saved_reports'));await assert.rejects(db.query('select * from achievement_private.minimum_rules_backup'));
 await admin(db);await add(9210,'مسودة جديدة غير منشورة');await add(9211,'منشور بلا حقول اختيارية',{status:'published',noDate:true});await add(9212,'منشور بلا حقول اختيارية',{status:'published',noDate:true});await add(9213,'منشور من نوع بديل',{status:'published',kind:'',details:{type:'مبادرة'}});await add(9214,'ممنوع لقائمة اختبار',{status:'published',details:{qa_marker:'qa'}});await add(9215,'غير منشور',{status:'published',details:{published:false}});await add(9216,'QA record',{status:'published'});
 await as(db,3);d=await dash();assert.equal(d.totals.reports,3);assert.equal(d.own_total,3);assert.ok(!JSON.stringify(d).includes('qa_marker'));await as(db,4);assert.equal((await dash()).own_total,0);
 await admin(db);await db.exec("update documentations set results='نتيجة اختيارية',edit_version=1 where id=9213");await as(db,3);assert.equal((await dash()).totals.reports,3);
 await admin(db);await db.exec("update documentations set edit_version=2 where id=9213");await as(db,3);assert.equal((await dash()).totals.reports,3);await as(db,1);await rpc(db,'review_achievement_report',{report_id:9213,decision:'excluded',expected_version:2,note:'استبعاد صريح'});assert.equal((await dash()).totals.reports,2);
 await admin(db);await db.exec("update documentations set edit_version=3 where id=9213");await as(db,3);assert.equal((await dash()).totals.reports,2);await assert.rejects(rpc(db,'review_achievement_report',{report_id:9202,decision:'approved',expected_version:0,note:''}));await as(db,0);await assert.rejects(dash());
 }finally{await db.close();}
});
test('archive save marks only successful insert as published; retries keep one report; local draft not submitted',async()=>{
 let saved=null,inserts=0;const client={from(){return {select(){return {limit:async()=>({}),eq(){return {eq(){return {maybeSingle:async()=>({data:saved})}}}}}},insert(row){saved={id:1};inserts++;assert.equal(row.status,'published');assert.equal(row.goal,null);assert.deepEqual(row.photo_files,[]);return {select(){return {single:async()=>({data:saved})}}}}}}};
 const submission={requestId:id(999),data:{activity:'عنوان موجز',type:'فعالية',executionScope:'internal'},files:[],attachments:[]};assert.equal(inserts,0);await saveSubmission(client,id(3),submission,async()=>{});await saveSubmission(client,id(3),submission,async()=>{});assert.equal(inserts,1);assert.equal(databaseRecord(id(3),submission).created_by,id(3));
});
