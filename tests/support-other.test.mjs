import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {JSDOM} from 'jsdom';
import {database,as,admin,id} from './complete/fixture.mjs';
import {installOtherChoices,validateOtherChoices,displayChoices,supportReports,SUPPORT_CENTER} from '../assets/js/documentation-choices.js';
import {databaseRecord} from '../assets/js/save-documentation.js';
test('all documentation Other inputs are conditional, required, restored, escaped and persisted without stale hidden values',async()=>{
 const dom=new JSDOM(await fs.readFile(new URL('../documentation.html',import.meta.url),'utf8'));const old=globalThis.document;globalThis.document=dom.window.document;const form=document.querySelector('.form'),ui=installOtherChoices(form);const $=id=>document.getElementById(id);
 assert.ok([...$('department').options].some(o=>o.value===SUPPORT_CENTER));assert.ok(document.querySelector('.committee-checks input[value="أخرى"]'));
 $('department').value='أخرى';ui.update();assert.equal($('departmentOther').required,true);let d=ui.collect({department:'أخرى',projects:[],committees:[],targets:[]});assert.throws(()=>validateOtherChoices(d),/يرجى التحديد/);
 $('departmentOther').value='قسم <تجريبي>';d=ui.collect(d);validateOtherChoices(d);assert.equal(displayChoices(d).department,'قسم <تجريبي>');
 $('department').value='العلوم';ui.update();assert.equal($('departmentOther').required,false);assert.equal($('departmentOther').parentElement.hidden,true);assert.equal(ui.collect({department:'العلوم'}).otherDetails.department,undefined);assert.equal($('departmentOther').value,'قسم <تجريبي>');
 $('department').value='أخرى';ui.restore(d);assert.equal($('departmentOther').value,'قسم <تجريبي>');
 for(const [key,cls] of [['projects','project'],['committees','committee'],['targets','target']]){form.querySelector('.'+cls+'-checks input[value="أخرى"]').checked=true;ui.update();$(key+'Other').value=key+' تجريبي';assert.equal($(key+'Other').required,true);}
 d=ui.collect({...d,projects:['اليونسكو','أخرى'],committees:['أخرى'],targets:['أخرى']});validateOtherChoices(d);const row=databaseRecord(id(5),{requestId:id(9030),data:d});assert.equal(row.department,'قسم <تجريبي>');assert.equal(row.projects,'اليونسكو • projects تجريبي');assert.deepEqual(row.details.projects,['اليونسكو','أخرى']);assert.equal(row.details.otherDetails.committees,'committees تجريبي');
 const normalized=displayChoices(d);assert.deepEqual(normalized.projects,['اليونسكو','projects تجريبي']);assert.equal(displayChoices({department:'أخرى'}).department,'أخرى');globalThis.document=old;dom.window.close();
});
test('center routing is a deduplicated view of original records; old workshop reports and privacy filters remain',()=>{
 const event={id:1,department:SUPPORT_CENTER,activity_type:'فعالية'},workshop={id:2,department:SUPPORT_CENTER,activity_type:'ورشة تدريبية'},old={id:3,activity_type:'ورشة تدريبية'},outside={id:4,department:'العلوم',activity_type:'مبادرة'};
 assert.deepEqual(supportReports([event,workshop,old,outside,{...event}, {...event,id:5,deleted_at:'2026-10-17'}]).map(r=>r.id),[1,2,3]);
});
test('standalone competition Other fields require specification and save display text',async()=>{
 const dom=new JSDOM(await fs.readFile(new URL('../competitions.html',import.meta.url),'utf8'),{runScripts:'outside-only'});dom.window.eval(await fs.readFile(new URL('../assets/js/competition-other.js',import.meta.url),'utf8'));const $=id=>dom.window.document.getElementById(id);$('department').value='أخرى';assert.throws(()=>dom.window.competitionOther(),/يرجى التحديد/);$('departmentOther').value='قسم تجريبي';dom.window.document.querySelector('[name=result][value="أخرى"]').checked=true;assert.throws(()=>dom.window.competitionOther(),/النتيجة/);$('resultOther').value='تكريم خاص تجريبي';let d=dom.window.competitionOther();assert.equal(d.department,'قسم تجريبي');assert.equal(d.result,'تكريم خاص تجريبي');$('department').value='العلوم';d=dom.window.competitionOther();assert.equal($('departmentOther').required,false);assert.equal($('departmentOther').value,'قسم تجريبي');assert.equal(d.department,'العلوم');dom.window.close();
});
test('real SQL: center coordinators read center activities only; Other is validated, tag links preserved, old reports unchanged',async()=>{
 const db=await database();await db.exec(await fs.readFile(new URL('../supabase/migrations/20261015050341_execution_scope_and_recognition.sql',import.meta.url),'utf8'));
 await as(db,5);const old=(await db.query("insert into documentations(created_by,request_id,activity,activity_type,department,details) values($1,$2,'اختبار قديم','نشاط','أخرى','{}') returning *",[id(5),id(9100)])).rows[0];await admin(db);
 await db.exec(await fs.readFile(new URL('../backend/support_center_other_choices.sql',import.meta.url),'utf8'));
 const insert=async(n,d)=>{await as(db,5);return(await db.query('insert into documentations(created_by,request_id,activity,activity_type,department,activity_date,details) values($1,$2,$3,$4,$5,$6,$7) returning *',[id(5),id(n),d.activity||'اختبار آلي مؤقت',d.type,d.department,'2026-10-17',d])).rows[0];};
 const reports=[];for(const [n,type]of [[9201,'فعالية'],[9202,'مبادرة'],[9203,'ورشة تدريبية']])reports.push(await insert(n,{type,department:SUPPORT_CENTER,projects:[],executionScope:'internal'}));
 await insert(9204,{type:'نشاط',department:'العلوم',projects:[]});
 await assert.rejects(insert(9205,{type:'نشاط',department:'أخرى',projects:[]}),/يرجى التحديد/);
 const custom=await insert(9206,{type:'أخرى',department:'أخرى',projects:['أخرى'],committees:['أخرى'],targets:['أخرى'],otherDetails:{type:'نشاط تجريبي مخصص',department:'قسم تجريبي مخصص',projects:'مشروع تجريبي مخصص',committees:'لجنة تجريبية مخصصة',targets:'فئة تجريبية مخصصة'}});
 assert.equal(custom.department,'قسم تجريبي مخصص');assert.equal(custom.projects,'مشروع تجريبي مخصص');assert.equal(custom.committees,'لجنة تجريبية مخصصة');assert.equal(custom.target_categories,'فئة تجريبية مخصصة');
 await as(db,7);const visible=(await db.query('select id from documentations order by id')).rows.map(r=>r.id);assert.deepEqual(visible,reports.map(r=>r.id));
 await as(db,6);assert.equal((await db.query('select count(*)::int n from documentations')).rows[0].n,0);
 await admin(db);assert.deepEqual((await db.query('select * from documentations where id=$1',[old.id])).rows[0],old);assert.equal((await db.query('select count(*)::int n from documentation_tags where documentation_id=$1',[custom.id])).rows[0].n,2);await db.close();
});
