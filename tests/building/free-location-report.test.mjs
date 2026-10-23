import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {GlobalFonts,createCanvas,loadImage} from '@napi-rs/canvas';import {PDFDocument} from 'pdf-lib';import {database,id,as,rpc,locations,payload} from './fixture.mjs';import {reportSections,KINDS} from '../../assets/js/building-model.js';import {drawSignatures,renderSignatures} from '../../assets/js/report-signatures.js';
const url=source=>'data:text/javascript;base64,'+Buffer.from(source).toString('base64');
test('saved free-text sites appear in actual Cairo A4 PDF pages without changing official signatures',async()=>{
 for(const weight of ['Regular','Bold'])GlobalFonts.registerFromPath(new URL('../../assets/fonts/Cairo-'+weight+'.ttf',import.meta.url).pathname,'Cairo');
 const pdfSource=await fs.readFile('assets/js/pdf-export.js','utf8');const {packPDF}=await import(url(pdfSource.slice(pdfSource.indexOf('export function packPDF'),pdfSource.indexOf('export async function renderPDF'))));
 globalThis.__buildingReportDeps={drawSignatures,renderSignatures,packPDF,reportSections,KINDS,ensureReportFonts:async()=>{}};
 const source=(await fs.readFile('assets/js/building-report.js','utf8')).replace(/^import .*;\n/gm,'');const {buildingCanvases,recordModel}=await import(url('const {'+Object.keys(globalThis.__buildingReportDeps).join(',')+'}=globalThis.__buildingReportDeps;\n'+source));
 const logo=await loadImage('school-logo.png'),db=await database(),all=[];try{await locations(db);await as(db,3);let n=800;
 for(const [kind,type,name]of [['cleanliness','toilet','دورة مياه الطالبات بجانب الإدارة'],['supplies','toilet','دورة مياه الطالبات بجانب الإدارة'],['toilet_maintenance','toilet','دورة مياه الطالبات بجانب الإدارة'],['building_maintenance','classroom','فصل السادس/1'],['building_maintenance','corridor','ممر الطابق الأول بجانب المختبر'],['building_maintenance','office','غرفة المعلمات']]){
  const record=await rpc(db,'save',{payload:{...payload(n++,kind),location_text:name,location_type:type,floor_id:id(100),is_test:true}}),trace=[];
  const pages=buildingCanvases(recordModel(record,[]),{logo,createCanvas(w,h){const c=createCanvas(w,h),g=c.getContext('2d'),draw=g.fillText.bind(g);g.fillText=(text,x,y)=>{trace.push(text);assert.ok(y>0&&y<1730);draw(text,x,y);};return c;}});
  assert.ok(trace.join(' ').includes(name));assert.equal(trace.filter(t=>t==='بإشراف').length,1);assert.ok(trace.includes('أ. هيا محمد النعيمي'));assert.equal(pages.length,1);all.push(...pages);
 }
 await fs.mkdir('.test-output/building',{recursive:true});const bytes=packPDF(all.map(c=>c.toBuffer('image/jpeg')));assert.equal((await PDFDocument.load(bytes)).getPageCount(),6);await fs.writeFile('.test-output/building/free-locations.pdf',bytes);await fs.writeFile('.test-output/building/free-location-first.png',all[0].toBuffer('image/png'));await fs.writeFile('.test-output/building/free-location-last.png',all.at(-1).toBuffer('image/png'));
 }finally{await db.close();}
});
