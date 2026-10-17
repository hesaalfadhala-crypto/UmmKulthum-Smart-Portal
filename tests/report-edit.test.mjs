import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {database,as,admin,id} from './complete/fixture.mjs';
const migration=await fs.readFile(new URL('../backend/report_editing.sql',import.meta.url),'utf8');
async function setup(){const db=await database();await db.exec(await fs.readFile(new URL('../supabase/migrations/20261015050341_execution_scope_and_recognition.sql',import.meta.url),'utf8'));await db.exec(await fs.readFile(new URL('../backend/support_center_other_choices.sql',import.meta.url),'utf8'));await db.query("update auth.users set email='e.k.abdulla@moe.bh' where id=$1",[id(3)]);await db.query("update profiles set role='coordinator' where id=$1",[id(3)]);await db.exec(migration);await db.exec(await fs.readFile(new URL('../backend/report-edit-audit-and-admin-authority.sql',import.meta.url),'utf8'));await db.query('insert into documentation_private.report_editors(user_id,manage_center) values($1,true)',[id(3)]);return db;}
test('designated coordinator updates original, keeps old media, adds her media on delegated report, owner edits and existing delegation, without delete grants',async()=>{
 const db=await setup();try{
 await as(db,5);const originalPath=id(5)+'/'+id(9010)+'/'+id(9011)+'.jpg';
 await db.query("insert into storage.objects(name,bucket_id,owner_id,metadata) values($1,'school-documentation-images',$2,'{\"size\":100}')",[originalPath,id(5)]);
 const oldPhoto={bucket:'school-documentation-images',path:originalPath,name:'old.jpg'};
 const row=(await db.query("insert into documentations(created_by,request_id,activity,activity_type,department,details,photo_files) values($1,$2,'تقرير اختبار','نشاط','مركز الدعم والتطوير المهني','{}',$3) returning *",[id(5),id(9010),[oldPhoto]])).rows[0];
 const unrelated=(await db.query("insert into documentations(created_by,request_id,activity,activity_type,department) values($1,$2,'تقرير خارج المركز','نشاط','العلوم') returning id",[id(5),id(9020)])).rows[0];
 await as(db,3);const token=id(9021),newPath=id(3)+'/'+token+'/'+id(9022)+'.jpg',pdfPath=id(3)+'/'+token+'/'+id(9023)+'.pdf';
 for(const [path,bucket]of [[newPath,'school-documentation-images'],[pdfPath,'school-report-files']])await db.query("insert into storage.objects(name,bucket_id,owner_id,metadata) values($1,$2,$3,'{\"size\":100}')",[path,bucket,id(3)]);
 assert.equal((await db.query('select report_edit_context($1) context',[row.id])).rows[0].context.can_edit,true);
 const updated=(await db.query('update documentations set activity=$1,photo_files=$2,attachment_files=$3,last_edit_request=$4 where id=$5 and edit_version=0 returning *',['تقرير معدّل',[oldPhoto,{bucket:'school-documentation-images',path:newPath,name:'new.jpg'}],[{bucket:'school-report-files',path:pdfPath,name:'new.pdf'}],token,row.id])).rows[0];
 assert.equal(updated.id,row.id);assert.equal(updated.created_by,id(5));assert.equal(updated.request_id,id(9010));assert.equal(updated.edit_version,1);assert.equal(updated.photo_files.length,2);assert.equal(updated.edited_by,id(3));
 assert.equal((await db.query('update documentations set activity=$1,last_edit_request=$2 where id=$3 returning id',['ممنوع',id(9025),unrelated.id])).rows.length,0);
 await assert.rejects(db.query('update documentations set created_by=$1 where id=$2',[id(3),row.id]),/permission denied/i);
 await assert.rejects(db.query('delete from documentations where id=$1',[row.id]),/permission denied/i);
 await assert.rejects(db.query('select set_report_deleted($1,true,0)',[row.id]),/الحذف والاستعادة/);
 await assert.rejects(db.query('update documentations set photo_files=$1,last_edit_request=$2 where id=$3',[[{bucket:'school-documentation-images',path:id(3)+'/'+id(9026)+'/'+id(9027)+'.jpg'}],id(9026),row.id]),/المرفق الجديد/);
 // Detaching one photo retains the blob and records a recoverable previous snapshot.
 await db.query('update documentations set photo_files=$1,last_edit_request=$2 where id=$3 and edit_version=1',[[oldPhoto],id(9030),row.id]);
 await as(db,4);assert.equal((await db.query('select report_edit_context($1) context',[row.id])).rows[0].context.can_edit,false);assert.equal((await db.query('update documentations set activity=$1,last_edit_request=$2 where id=$3 returning id',['ممنوع',id(9031),row.id])).rows.length,0);
 await as(db,5);assert.equal((await db.query('update documentations set activity=$1,last_edit_request=$2 where id=$3 returning id',["تعديل المالكة",id(9032),row.id])).rows.length,1);
 await admin(db);assert.equal((await db.query('select count(*) n from documentations')).rows[0].n,2);assert.equal((await db.query('select count(*) n from documentation_private.report_edit_history')).rows[0].n,3);assert.equal((await db.query('select count(*) n from storage.objects')).rows[0].n,3);
 }finally{await db.close();}
});

test('save client uploads additions, updates same id, recovers a lost response, rejects stale versions without inserting',async()=>{
 const {createCanvas,Image:NativeImage}=await import('@napi-rs/canvas');const {saveReportEdit}=await import('../assets/js/edit-documentation.js');
 const objects=new Map();let n=0;const prevURL=URL.createObjectURL,prevRevoke=URL.revokeObjectURL;URL.createObjectURL=b=>{const k='qa:'+n++;objects.set(k,b);return k;};URL.revokeObjectURL=k=>objects.delete(k);
 globalThis.Image=function(){const image=new NativeImage(),desc=Object.getOwnPropertyDescriptor(NativeImage.prototype,'src');Object.defineProperty(image,'src',{set(v){objects.get(v).arrayBuffer().then(b=>desc.set.call(image,Buffer.from(b)));}});return image;};
 globalThis.document={createElement(){const c=createCanvas(1,1);c.toBlob=async(cb)=>cb(new Blob([await c.encode('jpeg')]));return c;}};
 const db=await setup();try{await as(db,3);const original=(await db.query("insert into documentations(created_by,request_id,activity,activity_type,department) values($1,$2,'اختبار حفظ','نشاط','مركز الدعم والتطوير المهني') returning *",[id(3),id(9100)])).rows[0];
 let mutations=0,uploads=0,loseResponse=true,failWrite=false;
 class Q{constructor(){this.filters=[];}select(c){this.columns=c;return this;}eq(k,v){this.filters.push([k,v]);return this;}update(v){this.value=v;return this;}async single(){try{await as(db,3);let rows;if(this.value){mutations++;if(failWrite)return {error:{message:'خطأ اختبار مؤقت'}};const keys=Object.keys(this.value),vals=Object.values(this.value),params=[...vals,...this.filters.map(f=>f[1])];rows=(await db.query('update documentations set '+keys.map((k,i)=>k+'=$'+(i+1)).join(',')+' where '+this.filters.map(([k],i)=>k+'=$'+(vals.length+i+1)).join(' and ')+' returning '+this.columns,params)).rows;if(loseResponse){loseResponse=false;throw Error('lost response');}}else rows=(await db.query('select '+this.columns+' from documentations where '+this.filters.map(([k],i)=>k+'=$'+(i+1)).join(' and '),this.filters.map(f=>f[1]))).rows;return {data:rows[0]};}catch(e){return {error:{message:e.message}};}}}
 const api={from(t){assert.equal(t,'documentations');return new Q();},async rpc(name,args){return {data:(await db.query('select '+name+'($1) data',[args.report_id])).rows[0].data};},storage:{from(bucket){return {async upload(path,blob){uploads++;await db.query('insert into storage.objects(name,bucket_id,owner_id,metadata) values($1,$2,$3,$4)',[path,bucket,id(3),{size:blob.size}]);return {};}};}}};
 const canvas=createCanvas(30,20),image=new File([canvas.toBuffer('image/png')],'test.png',{type:'image/png'}),pdf=new File(['%PDF-1.7\n test'],'test.pdf',{type:'application/pdf'});
 const edit={id:original.id,version:0,requestId:id(9101),data:{activity:'اختبار معدّل',type:'نشاط',department:'مركز الدعم والتطوير المهني',projects:[],committees:[],targets:[]},files:[image],attachments:[pdf],retainedPhotos:[],retainedAttachments:[]};let checkpoints=0;
 const saved=await saveReportEdit(api,id(3),edit,async()=>checkpoints++);assert.equal(saved.id,original.id);assert.equal(saved.edit_version,1);assert.equal(mutations,1);assert.equal(uploads,2);assert.ok(checkpoints>=3);
 await saveReportEdit(api,id(3),edit,async()=>{});assert.equal(mutations,1);assert.equal(uploads,2);
 await assert.rejects(saveReportEdit(api,id(3),{...edit,requestId:id(9102)},async()=>{}),/تغير التقرير/);
 failWrite=true;const rejected={...edit,version:1,requestId:id(9103),files:[],attachments:[],uploaded:[],uploadedAttachments:[],sent:false};await assert.rejects(saveReportEdit(api,id(3),rejected,async()=>{}),/خطأ اختبار مؤقت/);assert.equal(rejected.sent,false);
 assert.equal((await db.query('select count(*) n from documentations')).rows[0].n,1);
 }finally{URL.createObjectURL=prevURL;URL.revokeObjectURL=prevRevoke;await db.close();}
});
