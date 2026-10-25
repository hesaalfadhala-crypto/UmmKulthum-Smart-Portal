import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';
import {PDFDocument,rgb} from 'pdf-lib';import {createCanvas,DOMMatrix,ImageData,Path2D} from '@napi-rs/canvas';
globalThis.DOMMatrix=DOMMatrix;globalThis.ImageData=ImageData;globalThis.Path2D=Path2D;
const pdfjs=await import(process.env.PDFJS_TEST_MODULE||'pdfjs-dist/legacy/build/pdf.mjs');
const root=new URL('../../',import.meta.url),read=p=>fs.readFile(new URL(p,root),'utf8');
const moduleURL=s=>'data:text/javascript;base64,'+Buffer.from(s).toString('base64');
const source=await read('assets/js/pdf-attachments.js');
let downloaded=[],assets=new Map();globalThis.window={PDFLib:{PDFDocument},requestAnimationFrame:cb=>queueMicrotask(cb),cancelAnimationFrame(){}};
globalThis.__attachmentClient={storage:{from(bucket){return {async download(path){downloaded.push({bucket,path});const data=assets.get(path);return data?{data}:{error:Error('denied')};}}}}};
const attachments=await import(moduleURL(source.replace(/^import .*;\n/gm,'const client=globalThis.__attachmentClient;\n')));
const previewSource=await read('assets/js/pdf-attachment-preview.js');
globalThis.__downloadAttachment=attachments.downloadAttachment;
const preview=await import(moduleURL(previewSource.replace(/^import .*;\n/gm,'const downloadAttachment=globalThis.__downloadAttachment;\n')));
const opts={getRenderer:async()=>({getDocument:options=>pdfjs.getDocument({...options,standardFontDataUrl:new URL('node_modules/pdfjs-dist/standard_fonts/',root).pathname,cMapUrl:new URL('node_modules/pdfjs-dist/cmaps/',root).pathname})}),createCanvas:()=>createCanvas(1,1)};
const exportSource=await read('assets/js/pdf-export.js');
const {packPDF}=await import(moduleURL(exportSource.slice(exportSource.indexOf('export function packPDF'),exportSource.indexOf('export async function renderPDF'))));
const signatures=await import(moduleURL(await read('assets/js/report-signatures.js')));
let outputPages=[],printFrame,downloadedPDF;
globalThis.__reportDeps={...signatures,appendAttachments:attachments.appendAttachments,attachmentCanvases:files=>preview.attachmentCanvases(files,opts),packPDF,extraSections:()=>[],isRecognition:()=>false,reportFields:d=>[['الهدف',d.goal]],ensureReportFonts:async()=>{}};
let pagesSource=(await read('assets/js/report-pages.js')).replace(/^import .*;\n/gm,'');
pagesSource=pagesSource.replace(/export async function prepareReport\([\s\S]*?(?=export function reportPDF)/,'export async function prepareReport(record,mode){return globalThis.__prepare(record,mode);}\n');
const reports=await import(moduleURL('const {'+Object.keys(globalThis.__reportDeps).join(',')+'}=globalThis.__reportDeps;\n'+pagesSource));
function node(tag){return {tag,children:[],style:{},setAttribute(){},append(...children){this.children.push(...children);},replaceChildren(...children){this.children=children;},addEventListener(){},remove(){},click(){if(tag==='a')downloadedPDF=this.href;},decode:async()=>{}};}
const makeDoc=()=>{const body=node('body');return {body,open(){},write(text){this.html=text;},close(){},createElement:node,get images(){return body.children.map(div=>div.children[0]);}};};
globalThis.document={body:node('body'),createElement(tag){if(tag!=='iframe')return node(tag);printFrame=node(tag);printFrame.contentDocument=makeDoc();printFrame.contentWindow={addEventListener(){},focus(){},print(){printFrame.printed=true;}};return printFrame;}};
const originalURL=URL.createObjectURL;const blobs=new Map();URL.createObjectURL=blob=>{const key='blob:test-'+blobs.size;blobs.set(key,blob);return key;};URL.revokeObjectURL=()=>{};
// Timer cleanup is not part of these tests and must not keep Node alive for 30 seconds.
const nativeSetTimeout=globalThis.setTimeout;globalThis.setTimeout=(fn,ms,...args)=>ms>=20000?{unref(){}}:nativeSetTimeout(fn,ms,...args);
const logo=createCanvas(1000,110);logo.getContext('2d').fillRect(0,0,1000,110);
const photo=createCanvas(800,500);photo.getContext('2d').fillStyle='#ee3344';photo.getContext('2d').fillRect(0,0,800,500);
const record={id:'SYNTHETIC-PDF-TEST',photos:[{url:'photo-private'}],data:{activity:'اختبار المرفقات',type:'فعالية',goal:'تقرير تجريبي فقط',academicYear:'2026–2027',reportPreparedBy:'معدّة تجريبية',reportSupervisors:['assistant']}};
globalThis.__prepare=async(r,mode)=>{assert.ok(r.photos.length>=1,'report photos retained');outputPages=reports.reportCanvases(r,mode,{logo,photos:Array(r.photos.length).fill(photo),createCanvas});return outputPages;};
async function sourcePDF(count){const pdf=await PDFDocument.create();const embedded=await pdf.embedPng(photo.toBuffer('image/png'));for(let i=0;i<count;i++){const p=pdf.addPage(i%2?[842,595]:[595,842]);p.drawRectangle({x:0,y:0,width:p.getWidth(),height:p.getHeight(),color:rgb(1,1,1)});p.drawText('SYNTHETIC ATTACHMENT PAGE '+(i+1),{x:30,y:40,size:18});p.drawImage(embedded,{x:70,y:100,width:400,height:250});}return new Blob([await pdf.save()],{type:'application/pdf'});}
test('real report image + all PDF attachment pages: download, print, preview, private buckets, failures and privacy cancellation',async()=>{
 await fs.mkdir(new URL('.test-output/',root),{recursive:true});
 assets.set('report.pdf',await sourcePDF(2));assets.set('certificate.pdf',await sourcePDF(1));
 const files=[{bucket:'school-report-files',path:'report.pdf',name:'تقرير تجريبي.pdf'},{bucket:'school-competition-files',path:'certificate.pdf',name:'شهادة تجريبية.pdf'}];
 const r={...record,attachment_files:files};
 await reports.outputReport(r,'auto',false);assert.ok(downloadedPDF);
 const bytes=new Uint8Array(await blobs.get(downloadedPDF).arrayBuffer()),pdf=await PDFDocument.load(bytes);
 assert.equal(pdf.getPageCount(),outputPages.length+3);assert.equal(pdf.getPage(outputPages.length+1).getWidth(),842,'landscape attachment preserved');
 await fs.writeFile(new URL('.test-output/report-with-attachments.pdf',root),bytes);
 const parsed=await pdfjs.getDocument({data:bytes.slice(),isEvalSupported:false,standardFontDataUrl:new URL('node_modules/pdfjs-dist/standard_fonts/',root).pathname}).promise;
 for(let i=outputPages.length+1;i<=parsed.numPages;i++){const page=await parsed.getPage(i);const text=(await page.getTextContent()).items.map(x=>x.str).join(' ');assert.match(text,/SYNTHETIC ATTACHMENT PAGE/);}await parsed.destroy();
 await reports.outputReport(r,'auto',true);assert.equal(printFrame.printed,true);assert.equal(printFrame.contentDocument.images.length,pdf.getPageCount());assert.match(printFrame.contentDocument.html,/object-fit:contain/);
 const canvases=await preview.attachmentCanvases(files,opts);assert.equal(canvases.length,3);assert.ok(canvases[1].width>canvases[1].height,'preview preserves rotated shape');
 const imageData=canvases[0].getContext('2d').getImageData(0,0,canvases[0].width,canvases[0].height).data;let red=0;for(let i=0;i<imageData.length;i+=4)if(imageData[i]>180&&imageData[i+1]<100)red++;assert.ok(red>50000,'embedded photo rendered visibly');
 await fs.writeFile(new URL('.test-output/attachment-preview.png',root),canvases[0].toBuffer('image/png'));
 assert.ok(downloaded.some(d=>d.bucket==='school-competition-files'));assert.ok(downloaded.some(d=>d.bucket==='school-report-files'));
 assert.equal(await attachments.appendAttachments(bytes,[]),bytes);assert.deepEqual(await preview.attachmentCanvases([],opts),[]);
 await assert.rejects(()=>attachments.downloadAttachment({bucket:'unknown',path:'report.pdf'}),/غير صالح/);
 await assert.rejects(()=>attachments.appendAttachments(bytes,[{path:'denied.pdf',name:'missing'}]),/تعذر تنزيل/);
 assets.set('bad.pdf',new Blob(['not a PDF']));await assert.rejects(()=>attachments.appendAttachments(bytes,[{path:'bad.pdf',name:'bad'}]),/تعذر دمج/);
 await assert.rejects(()=>preview.attachmentCanvases([{path:'bad.pdf',name:'bad'}],opts),/تعذر عرض/);
 await reports.outputReport(record,'one',false);assert.equal((await PDFDocument.load(await blobs.get(downloadedPDF).arrayBuffer())).getPageCount(),1,'no attachments still exports exactly the report');const priorFrame=printFrame;await assert.rejects(()=>reports.outputReport({...r,attachment_files:[{path:'bad.pdf',name:'bad'}]},'auto',true),/تعذر عرض/);assert.equal(printFrame,priorFrame,'never prints a partial report');const previous=downloadedPDF;await assert.rejects(()=>reports.outputReport({...r,attachment_files:[{path:'bad.pdf',name:'bad'}]},'auto'),/تعذر دمج/);assert.equal(downloadedPDF,previous,'never downloads a partial report');
 let checks=0;assert.deepEqual(await preview.attachmentCanvases(files,{...opts,isCurrent:()=>++checks<2}),[],'privacy toggle cancels stale preview');
 // Expanded merge cases: exact original page counts and ordering, including ten photos.
 assets.set('three.pdf',await sourcePDF(3));assets.set('five.pdf',await sourcePDF(5));
 const refs=n=>({path:n+'.pdf',name:n+'.pdf'});
 for(const [baseGoal,photos,files]of [['قصير',record.photos,[refs('three')]],['شرح طويل '.repeat(200),record.photos,[refs('five')]],['عشر صور',Array(10).fill({url:'photo-private'}),[refs('three')]],['ملفان',record.photos,[refs('five'),refs('three')]]]){
 await reports.outputReport({...record,data:{...record.data,goal:baseGoal},photos,attachment_files:files},'auto',false);const merged=await PDFDocument.load(await blobs.get(downloadedPDF).arrayBuffer());if(baseGoal==='قصير')assert.equal(outputPages.length,1);if(baseGoal.startsWith('شرح طويل'))assert.equal(outputPages.length,2);assert.equal(merged.getPageCount(),outputPages.length+files.reduce((n,f)=>n+(f.path==='five.pdf'?5:3),0));assert.equal(merged.getPage(outputPages.length).getWidth(),595);assert.equal(merged.getPage(outputPages.length+1).getWidth(),842);if(photos.length===10){assert.ok(outputPages.length>=3);await fs.writeFile(new URL('.test-output/ten-photos-merged.pdf',root),new Uint8Array(await blobs.get(downloadedPDF).arrayBuffer()));}
 }
 await reports.outputReport(r,'auto',true,{includeAttachments:false});assert.equal(printFrame.contentDocument.images.length,outputPages.length,'base-only printing excludes all attachments');
 globalThis.setTimeout=nativeSetTimeout;URL.createObjectURL=originalURL;
});
