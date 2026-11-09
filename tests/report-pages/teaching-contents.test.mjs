import test from 'node:test';
import assert from 'node:assert/strict';
import {createCanvas} from '@napi-rs/canvas';
import {PDFDocument} from 'pdf-lib';
import {TEACHING_AREA, TEACHING_CONTENTS} from '../../assets/js/teaching-contents.js';
import {databaseRecord} from '../../assets/js/save-documentation.js';
globalThis.window = {supabase:{createClient:()=>({})}};
const {reportCanvases, reportPDF} = await import('../../assets/js/report-pages.js');

test('teaching file items persist on the original report, and appear in its single-page A4 PDF', async () => {
 const data = {activity:'تقرير تجريبي', type:'فعالية', department:'العلوم', areas:[TEACHING_AREA], teachingContents:['8','5','5','invalid']};
 const row = databaseRecord('synthetic', {data});
 assert.deepEqual(row.details.teachingContents, ['5','8']);
 assert.equal(row.department, 'العلوم');
 assert.equal(row.documentation_area, TEACHING_AREA);
 for (const areas of [[], ['الإنجاز الأكاديمي']]) {
  assert.equal(databaseRecord('synthetic', {data:{...data,areas}}).details.teachingContents, undefined);
 }
 const printed = [];
 const pages = reportCanvases({id:99,data:row.details},'auto',{
  logo:createCanvas(100,100),
  createCanvas(width,height){
   const canvas=createCanvas(width,height);
   const context=canvas.getContext('2d');
   const fillText=context.fillText.bind(context);
   context.fillText=(value,...args)=>{printed.push(value);return fillText(value,...args);};
   return canvas;
  }
 });
 assert.equal(pages.length,1);
 for (const label of [TEACHING_AREA,TEACHING_CONTENTS[4].label,TEACHING_CONTENTS[7].label]) assert.ok(printed.join(' ').includes(label));
 const pdf=await PDFDocument.load(reportPDF(pages));
 assert.equal(pdf.getPageCount(),1);
 assert.deepEqual(pdf.getPage(0).getSize(),{width:595.28,height:841.89});
});
