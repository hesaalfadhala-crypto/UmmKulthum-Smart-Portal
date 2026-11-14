import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import {PDFDocument} from 'pdf-lib';
import {proposal} from '../../assets/js/visit-import-model.js';
const wait=async fn=>{for(let i=0;i<200;i++){if(fn())return;await new Promise(r=>setTimeout(r,5));}throw Error('UI timed out');};
test('review UI resumes original PDF, requires review again after changes and handles duplicate without adding',async()=>{
 const context={teachers:[{id:'teacher',full_name:'معلمة اختبار',department:'الرياضيات',academic_year:'2026-2027'}],observers:[{id:'observer',full_name:'زائرة اختبار'}]};
 const item=proposal({pages:[1,2],teacher_name:'معلمة اختبار',observer_name:'زائرة اختبار',academic_year:'2026-2027',semester:1,visit_date:'2026-10-20',lesson_title:'المجموعات',class_section:'أول إعدادي/4',ratings:Array.from({length:18},(_,i)=>({criterion_id:i+1,level:3})),final_judgment:3},0,context);item.details.judgment_basis='حكم من الأصل';
 let batch={id:'batch',file_name:'forms.pdf',page_count:2,storage_path:'user/batch.pdf',proposals:[item],processed_pages:[1,2],created_at:new Date().toISOString()};let calls=0;
 const pdf=await PDFDocument.create();pdf.addPage();pdf.addPage();const blob=new Blob([await pdf.save()],{type:'application/pdf'});
 const api={auth:{getUser:async()=>({data:{user:{id:'user'}}})},rpc:async name=>{if(name==='classroom_import_context')return {data:context};if(name==='commit_classroom_pdf_visit'){calls++;return {data:{id:'existing-visit',duplicate:true}};}throw Error(name);},functions:{invoke:async()=>({data:{configured:false}})},storage:{from:()=>({download:async()=>({data:blob})})},from(table){let single=false,change;const q={select(){return q;},eq(){return q;},order(){return q;},limit(){return q;},single(){single=true;return q;},update(value){change=value;return q;},then(resolve,reject){if(change)batch={...batch,...change};const data=table==='classroom_import_batches'?(single?batch:[batch]):[];return Promise.resolve({data}).then(resolve,reject);}};return q;}};
 const dom=new JSDOM(await fs.readFile(new URL('../../visit-import.html',import.meta.url),'utf8'),{url:'https://hesaalfadhala-crypto.github.io/UmmKulthum-Smart-Portal/visit-import.html'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.location={replace(){throw Error('unexpected redirect');}};window.supabase={createClient:()=>api};window.PDFLib={PDFDocument};
 try{
 await import('../../assets/js/visit-import-ui.js?test='+Date.now());await wait(()=>document.querySelector('#history button'));assert.match(document.getElementById('serviceStatus').textContent,/بانتظار/);document.querySelector('#history button').click();await wait(()=>document.querySelectorAll('.rating-row').length===18);assert.match(document.getElementById('source').src,/#page=1/);assert.equal(document.getElementById('resumeExtraction').disabled,true);
 const form=document.getElementById('importReviewForm'),review=form.elements.reviewed;
 review.checked=true;review.dispatchEvent(new window.Event('change'));const title=form.elements.lesson_title;title.value='المجموعات والتصنيف';title.dispatchEvent(new window.Event('input'));assert.equal(review.checked,false);
 form.dispatchEvent(new window.Event('submit',{cancelable:true}));await new Promise(r=>setTimeout(r,10));assert.equal(calls,0);assert.match(document.querySelector('.error-list').textContent,/أكدي/);
 review.checked=true;review.dispatchEvent(new window.Event('change'));form.dispatchEvent(new window.Event('submit',{cancelable:true}));await wait(()=>document.getElementById('review').textContent.includes('موجودة مسبقًا'));assert.equal(calls,1);assert.match(document.getElementById('summary').textContent,/موجودة مسبقًا: 1/);assert.ok(document.querySelector('a[href="visit-edit.html?id=existing-visit"]'));assert.equal(batch.proposals[0].duplicate.id,'existing-visit');
 }finally{dom.window.close();}
});
