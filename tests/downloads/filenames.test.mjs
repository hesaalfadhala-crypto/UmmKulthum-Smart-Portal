import test from 'node:test';
import assert from 'node:assert/strict';
import {reportFilename,safeReportTitle,saveReportPDF} from '../../assets/js/report-filename.js';
import {zip} from '../../assets/js/visit-excel.js';
globalThis.window={supabase:{createClient:()=>({})}};
const {packPDF}=await import('../../assets/js/pdf-export.js');
import {writeFileSync} from 'node:fs';
test('Arabic titles, forbidden characters, reserved names and byte limits',()=>{
 assert.equal(reportFilename({title:'تقرير تفعيل استراتيجيات التعلم النشط'}),'تقرير تفعيل استراتيجيات التعلم النشط.pdf');
 assert.equal(safeReportTitle('  تجربة/علوم: نشاط*?  '),'تجربة علوم نشاط');
 assert.equal(safeReportTitle('...'),'تقرير');
 assert.equal(safeReportTitle('CON'),'تقرير CON');
 assert.ok(new TextEncoder().encode(reportFilename({title:'عنوان طويل '.repeat(100),id:836})).length<255);
 assert.equal(reportFilename({data:{activity:'العنوان'},id:836}),'العنوان.pdf');
});
test('distinct duplicates and actual single download metadata leave record unchanged',()=>{
 const used=new Set();assert.notEqual(reportFilename({title:'تقرير',id:1},used),reportFilename({title:'تقرير',id:2},used));
 assert.equal(reportFilename({title:'تقرير',id:1},used),'تقرير - 1.pdf');
 assert.equal(reportFilename({title:'تقرير',id:1},used),'تقرير - 1 (2).pdf');
 const record={id:836,data:{activity:'التعلم النشط'}},before=JSON.stringify(record);let link;
 globalThis.window={name:'',parent:null};window.parent=window;
 globalThis.document={createElement:()=>link={click(){this.clicked=true;}}};
 const timeout=globalThis.setTimeout;globalThis.setTimeout=()=>0;
 try{saveReportPDF(new Uint8Array([37,80,68,70,45]),record);assert.equal(link.download,'التعلم النشط.pdf');assert.equal(link.clicked,true);assert.equal(JSON.stringify(record),before);}finally{globalThis.setTimeout=timeout;delete globalThis.window;delete globalThis.document;}
});
test('ZIP stores separate Arabic PDF names and original binary bytes',()=>{
 const used=new Set(),files={},bytes=packPDF([new Uint8Array([255,216,255,217])]);
 for(const id of [836,837])files[reportFilename({title:'التعلم النشط',id},used)]=bytes;
 writeFileSync('/tmp/report-names-test.zip',zip(files));writeFileSync('/tmp/report-original-test.pdf',bytes);
});
