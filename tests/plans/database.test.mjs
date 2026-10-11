import test from 'node:test';import assert from 'node:assert/strict';import {database,as,admin,id,rpc,body,saveArgs} from './fixture.mjs';
test('weekly plans: real SQL lifecycle, publication snapshots, roster, RLS and private Storage',async t=>{
 const {db,period}=await database();let principal,teacher;
 const decide=(p,status,version,op,note='ملاحظات اختبار واضحة')=>rpc(db,'decide_weekly_plan',{plan_uuid:p,decision:status,note,expected_version:version,operation_id:id(op)});
 await t.test('principal draft stays private; delegates are explicit and full assistant cannot publish implicitly',async()=>{
  principal=await rpc(db,'save_weekly_plan',saveArgs(period,1,'principal'));
  await as(db,5);assert.equal((await db.query('select count(*)::int n from weekly_plans')).rows[0].n,0);assert.equal((await db.query('select count(*)::int n from weekly_publications')).rows[0].n,0);
  await as(db,2);await assert.rejects(decide(principal.id,'published',1,1001),e=>e.code==='42501');
  await as(db,1);await decide(principal.id,'published',1,1002);
  await as(db,5);assert.equal((await db.query('select count(*)::int n from weekly_publications')).rows[0].n,1);assert.match((await db.query('select message from weekly_notifications')).rows[0].message,/خطة مديرة المدرسة/);assert.equal((await db.query('select count(*)::int n from weekly_plans')).rows[0].n,0);
 });
 await t.test('editing a published principal plan cannot leak draft changes; republication notifies once on retry',async()=>{
  await as(db,1);const args=saveArgs(period,1,'principal',2,1003);args.payload.body=body('تعديل لم ينشر بعد');await rpc(db,'save_weekly_plan',args);
  await as(db,5);assert.equal((await db.query('select body from weekly_publications')).rows[0].body.slots[0].text,'مهمة اختبار واضحة');
  await as(db,1);await decide(principal.id,'published',3,1004);await decide(principal.id,'published',3,1004);
  await as(db,5);assert.equal((await db.query('select body from weekly_publications')).rows[0].body.slots[0].text,'تعديل لم ينشر بعد');assert.equal((await db.query('select count(*)::int n from weekly_notifications')).rows[0].n,2);
 });
 await t.test('teacher save/submission survives retry and reviewers see only their authorized departments',async()=>{
  await as(db,5);const args=saveArgs(period,5,'staff',0,1010);args.payload.submit=true;teacher=await rpc(db,'save_weekly_plan',args);assert.deepEqual(await rpc(db,'save_weekly_plan',args),teacher);
  await assert.rejects(rpc(db,'save_weekly_plan',{...args,payload:{...args.payload,body:body('مختلف')}}),/بيانات مختلفة/);
  await as(db,6);assert.equal((await db.query('select count(*)::int n from weekly_plans')).rows[0].n,0);await assert.rejects(rpc(db,'weekly_accounts'),e=>e.code==='42501');
  await as(db,7);assert.equal((await db.query('select count(*)::int n from weekly_plans')).rows[0].n,0);await assert.rejects(decide(teacher.id,'approved',1,1011),e=>e.code==='42501');
  for(const n of[1,2,3,4]){await as(db,n);assert.equal((await db.query('select count(*)::int n from weekly_plans where id=$1',[teacher.id])).rows[0].n,1);}
  await as(db,3);await decide(teacher.id,'needs_revision',1,1012);await assert.rejects(decide(teacher.id,'approved',1,1013),e=>e.code==='40001');
  await as(db,5);let updated=saveArgs(period,5,'staff',2,1014);updated.payload.submit=true;await rpc(db,'save_weekly_plan',updated);
  await as(db,1);await decide(teacher.id,'approved',3,1015);
  await as(db,5);assert.equal((await db.query('select status from weekly_plans where id=$1',[teacher.id])).rows[0].status,'approved');assert.match((await db.query("select message from weekly_notifications where event='approved'")).rows[0].message,/اعتماد/);
 });
 await t.test('private files are immutable, validated by ownership and published only with their plan',async()=>{
  await as(db,5);const file=id(4000),path=id(5)+'/'+teacher.id+'/'+file+'.xlsx';await db.query("insert into storage.objects(bucket_id,name,owner_id) values('weekly-plan-files',$1,$2)",[path,id(5)]);
  const args={plan_uuid:teacher.id,file_uuid:file,object_path:path,original_name:'خطة اختبار.xlsx',mime_type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',operation_id:id(1020)};
  await rpc(db,'attach_weekly_file',args);await rpc(db,'attach_weekly_file',args);assert.equal((await db.query('select count(*)::int n from weekly_files')).rows[0].n,1);
  await as(db,6);assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,0);await assert.rejects(rpc(db,'attach_weekly_file',{...args,operation_id:id(1021)}),e=>e.code==='42501');
  await as(db,3);assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,1);
  await as(db,5);assert.equal((await db.query('delete from storage.objects where name=$1 returning name',[path])).rows.length,0);
  await as(db,1);const pdf=id(4001),p=id(1)+'/'+principal.id+'/'+pdf+'.pdf';await db.query("insert into storage.objects(bucket_id,name,owner_id) values('weekly-plan-files',$1,$2)",[p,id(1)]);await rpc(db,'attach_weekly_file',{plan_uuid:principal.id,file_uuid:pdf,object_path:p,original_name:'خطة المديرة.pdf',mime_type:'application/pdf',operation_id:id(1022)});
  const updated=saveArgs(period,1,'principal',4,1023);updated.payload.file_id=pdf;await rpc(db,'save_weekly_plan',updated);
  await as(db,7);assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,0);
  await as(db,1);await decide(principal.id,'published',5,1024);
  await as(db,7);assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,1);
 });
 await t.test('directory/count population includes unemailed names but author identity cannot be forged',async()=>{
  await as(db,1);assert.equal((await db.query('select count(*)::int n from weekly_staff')).rows[0].n,4);assert.equal((await db.query('select count(*)::int n from weekly_assignments where required')).rows[0].n,4);
  await as(db,8);await assert.rejects(rpc(db,'save_weekly_plan',saveArgs(period,8,'staff',0,1030)),e=>e.code==='42501');await as(db,5);const forged=saveArgs(period,7,'staff',0,1031);await assert.rejects(rpc(db,'save_weekly_plan',forged),e=>e.code==='42501');await assert.rejects(db.query("update weekly_plans set status='approved'"),/permission denied/);await assert.rejects(rpc(db,'configure_weekly_plans',{payload:{action:'staff',id:id(105),user_id:id(6)}}),e=>e.code==='42501');
  await db.exec(`set request.jwt.claims='{"user_metadata":{"role":"principal","school_access":"all"}}'`);assert.equal((await rpc(db,'weekly_context')).full_access,false);
 });
 await t.test('anonymous and accounts without a school profile cannot read or use APIs; notifications immutable except read_at',async()=>{
  await as(db,5);await db.query('update weekly_notifications set read_at=now()');await assert.rejects(db.query("update weekly_notifications set message='forged'"),/permission denied/);
  await as(db,9);assert.equal((await db.query('select count(*)::int n from weekly_publications')).rows[0].n,0);await assert.rejects(rpc(db,'weekly_context'),e=>e.code==='42501');
  await as(db,null);await assert.rejects(db.query('select * from weekly_publications'),/permission denied/);await assert.rejects(rpc(db,'weekly_context'),/permission denied/);
 });
 await admin(db);const dump=await db.dumpDataDir();await db.close();const {PGlite}=await import('@electric-sql/pglite');const restored=new PGlite({loadDataDir:dump});await as(restored,5);assert.equal((await restored.query('select status from weekly_plans where id=$1',[teacher.id])).rows[0].status,'approved');assert.equal((await restored.query('select count(*)::int n from weekly_publications')).rows[0].n,1);await restored.close();
});
