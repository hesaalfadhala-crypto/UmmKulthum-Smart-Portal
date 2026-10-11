import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import {database,as,admin,id,rpc} from './fixture.mjs';
import {saveSubmission} from '../../assets/js/save-documentation.js';

test('six center services: actual DOM forms → SQL → closed/reopened page → coordinator review → original workshop archive',async()=>{
 const db=await database();let actor=5,loseResponse=false,dom,sequence=0,prints=0;
 const api={auth:{getUser:async()=>({data:{user:{id:id(actor)}},error:null})},from:table=>new Query(table),rpc:async(name,args={})=>{
  try{await as(db,actor);const result=await rpc(db,name,args);if(loseResponse&&name==='save_support_request'){loseResponse=false;return {data:null,error:{message:'انقطع الاتصال بعد الحفظ'}};}return {data:result,error:null};}catch(e){return {data:null,error:{code:e.code,message:e.message}};}
 }};
 class Query{
  constructor(table){assert.match(table,/^[a-z_]+$/);this.table=table;this.columns='*';this.filters=[];this.orders=[];}
  select(v){assert.match(v,/^[a-z_*,]+$/);this.columns=v;return this;}
  eq(k,v){assert.match(k,/^[a-z_]+$/);this.filters.push([k,v]);return this;}
  order(k,options={}){assert.match(k,/^[a-z_]+$/);this.orders.push(k+(options.ascending===false?' desc':' asc'));return this;}
  range(a,b){this.start=a;this.count=b-a+1;return this;}
  limit(n){this.count=n;return this;}
  insert(v){this.value=v;return this;}
  single(){this.one=true;return this.run();}maybeSingle(){this.one=true;return this.run();}
  then(resolve,reject){return this.run().then(resolve,reject);}
  async run(){try{await as(db,actor);let query,params=[];if(this.value){const keys=Object.keys(this.value);params=Object.values(this.value).map(v=>v&&typeof v==='object'?JSON.stringify(v):v);query=`insert into ${this.table}(${keys.join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')}) returning ${this.columns}`;}else{
   query=`select ${this.columns} from ${this.table}`;if(this.filters.length){params=this.filters.map(x=>x[1]);query+=' where '+this.filters.map((x,i)=>x[0]+'=$'+(i+1)).join(' and ');}if(this.orders.length)query+=' order by '+this.orders.join(',');if(this.count!=null)query+=' limit '+this.count;if(this.start)query+=' offset '+this.start;
  }const rows=(await db.query(query,params)).rows.map(row=>Object.fromEntries(Object.entries(row).map(([k,v])=>[k,v instanceof Date?(['activity_date','applied_on'].includes(k)?v.toISOString().slice(0,10):v.toISOString()):v])));return {data:this.one?rows[0]||null:rows,error:null};}catch(e){return {data:null,error:{code:e.code,message:e.message}};}}
 }
 const html=await fs.readFile(new URL('../../training.html',import.meta.url),'utf8');
 async function mount(n,storage={}){if(dom){dom.window.dispatchEvent(new dom.window.Event('pagehide'));dom.window.close();}actor=n;dom=new JSDOM(html,{url:'https://school.invalid/training.html'});for(const [k,v]of Object.entries(storage))dom.window.localStorage.setItem(k,v);dom.window.supabase={createClient:()=>api};dom.window.print=()=>prints++;globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.location=dom.window.location;await import('../../assets/js/support-center.js?test='+sequence++);assert.match(document.getElementById('centerStatus').textContent,/المركز جاهز/);}
 async function waitFor(check){for(let n=0;n<200;n++){if(check())return;await new Promise(r=>setTimeout(r,5));}assert.fail('UI operation did not finish');}
 function fill(formId,values){const form=document.getElementById(formId);for(const [name,v]of Object.entries(values)){const input=form.querySelector('[name="'+name+'"]');input.value=v;input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));}return form;}
 async function submit(formId,values,done){const form=fill(formId,values);form.dispatchEvent(new dom.window.Event('submit',{cancelable:true,bubbles:true}));await waitFor(()=>!form.querySelector('button[type=submit]').disabled&&done(form.querySelector('.form-message').textContent));return form;}
 try{
  await mount(5);for(const b of document.querySelectorAll('[data-service]')){b.click();assert.equal(document.querySelector('[data-panel="'+b.dataset.service+'"]').hidden,false);}assert.equal(document.querySelectorAll('[data-service]').length,6);
  loseResponse=true;let form=await submit('bookingForm',{title:'حجز اختبار واضح',date:'2098-10-11',from:'09:00',to:'10:00'},text=>text.includes('انقطع'));assert.equal(form.querySelector('[name=title]').disabled,true);
  const stored=Object.fromEntries(Object.keys(window.localStorage).map(k=>[k,window.localStorage.getItem(k)]));await mount(5,stored);form=document.getElementById('bookingForm');assert.match(form.querySelector('.form-message').textContent,/استُعيدت محاولة/);form.dispatchEvent(new dom.window.Event('submit',{cancelable:true,bubbles:true}));await waitFor(()=>form.querySelector('.form-message').textContent.includes('رقم السجل'));assert.equal(form.querySelector('[name=title]').disabled,false);await admin(db);assert.equal((await db.query("select count(*)::int n from support_requests where kind='booking'")).rows[0].n,1);
  await submit('needForm',{title:'احتياج اختبار مهني',details:'تطبيق أدوات تقويم'},text=>text.includes('رقم السجل'));assert.match(document.getElementById('needsList').textContent,/احتياج اختبار/);
  form=await submit('proposalForm',{title:'ورشة اختبار للربط',date:'2098-10-11',from:'11:00',to:'10:00',details:'محاور اختبار'},text=>text.includes('نهاية بعد البداية'));assert.equal(form.querySelector('[name=title]').disabled,false);
  await submit('proposalForm',{to:'12:00'},text=>text.includes('رقم السجل'));assert.match(document.getElementById('proposalsList').textContent,/قيد المراجعة/);
  await mount(4);assert.match(document.getElementById('bookingsList').textContent,/حجز اختبار واضح/);const proposal=document.getElementById('proposalsList');const note=proposal.querySelector('textarea');note.value='ملاحظة مراجعة اختبار';note.dispatchEvent(new dom.window.Event('input'));document.getElementById('refreshCenter').click();await waitFor(()=>!document.getElementById('refreshCenter').disabled);assert.equal(proposal.querySelector('textarea').value,'ملاحظة مراجعة اختبار');[...proposal.querySelectorAll('button')].find(b=>b.textContent.includes('اعتماد وإضافة')).click();await waitFor(()=>document.getElementById('programsList').textContent.includes('ورشة اختبار للربط'));
  await admin(db);const program=(await db.query('select id from support_programs')).rows[0];assert.ok(program.id);
  actor=5;const saved=await saveSubmission(api,id(5),{requestId:id(3333),data:{activity:'تقرير ورشة اختبار',type:'ورشة تدريبية',date:'2026-10-11',centerProgramId:program.id,trainingBeneficiaries:'15',executor:'مستخدمة اختبار'},files:[],uploaded:[]},async()=>{});await mount(3);assert.match(document.getElementById('reportsList').textContent,/تقرير ورشة اختبار/);const reportLink=document.querySelector('#reportsList a');assert.equal(reportLink.getAttribute('href'),'report.html?id='+saved.id);assert.match(document.getElementById('reportsList').textContent,/15/);assert.equal(document.getElementById('stat-workshops').textContent,'1');assert.equal(document.getElementById('stat-beneficiaries').textContent,'15');document.getElementById('printCenter').click();assert.equal(prints,1);
  await mount(5);await submit('impactForm',{target:'program:'+program.id,application:'تطبيق مهني اختبار',applied_on:'2026-10-11',before_level:'2',after_level:'4'},text=>text.includes('رقم السجل'));assert.match(document.getElementById('impactsList').textContent,/تطبيق مهني اختبار/);await mount(4);assert.match(document.getElementById('impactsList').textContent,/تطبيق مهني اختبار/);
  await mount(6);assert.doesNotMatch(document.getElementById('bookingsList').textContent,/حجز اختبار واضح/);assert.doesNotMatch(document.getElementById('impactsList').textContent,/تطبيق مهني اختبار/);assert.doesNotMatch(document.getElementById('reportsList').textContent,/تقرير ورشة اختبار/);assert.match(document.getElementById('programsList').textContent,/ورشة اختبار للربط/);
  await admin(db);assert.equal((await db.query('select count(*)::int n from documentations')).rows[0].n,1);
 }finally{if(dom){dom.window.dispatchEvent(new dom.window.Event('pagehide'));dom.window.close();}await db.close();}
});
