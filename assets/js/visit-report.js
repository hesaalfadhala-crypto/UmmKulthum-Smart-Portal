import {context,report,status,showIdentity,handleError} from './visit-data.js';
import {analyze,compare} from './visit-analysis.js';
import {renderReport} from './visit-view.js';
import {renderVisitPDF} from './visit-pdf.js';
import {renderExcel} from './visit-excel.js';
let record,a,b;const buttons=['pdf','excel','print'].map(id=>document.getElementById(id));
function download(bytes,type,name){const url=URL.createObjectURL(new Blob([bytes],{type}));const link=document.createElement('a');link.href=url;link.download=name;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
async function init(){try{const ctx=await context();showIdentity(ctx);record=await report(new URLSearchParams(location.search).get('id')||'');a=analyze(record.snapshot);b=record.comparison_snapshot?analyze(record.comparison_snapshot):null;const node=document.getElementById('report');renderReport(node,record,a,b?compare(a,b):null);node.hidden=false;buttons.forEach(b=>b.disabled=false);status('تقرير محفوظ للقراءة فقط. يعرض النتائج وقت الإصدار دون تعديل الزيارات الأصلية.');}catch(e){handleError(e);}}
document.getElementById('pdf').addEventListener('click',async()=>{buttons.forEach(b=>b.disabled=true);try{status('جار تجهيز التقرير والصور والخط العربي…');const bytes=await renderVisitPDF(record,a,b);download(bytes,'application/pdf','UmmKulthum-visits-'+record.id+'.pdf');status('تم تجهيز ملف PDF.');}catch(e){handleError(e);}finally{buttons.forEach(b=>b.disabled=false);}});
document.getElementById('excel').addEventListener('click',()=>{try{download(renderExcel(record,a,b),'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','UmmKulthum-visits-'+record.id+'.xlsx');status('تم تجهيز Excel بالنسب والأعداد والزيارات.');}catch(e){handleError(e);}});
document.getElementById('print').addEventListener('click',async()=>{await document.fonts.ready;await Promise.all([...document.querySelectorAll('#report img')].map(img=>img.decode()));window.print();});void init();
