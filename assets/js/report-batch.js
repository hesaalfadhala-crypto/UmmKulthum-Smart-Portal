import {reportFilename} from './report-filename.js';
import {zip} from './visit-excel.js';
// Use each report's existing authenticated renderer, including its attachments.
export async function downloadReportBatch(entries,status=()=>{}) {
  if(!entries.length)throw Error('لا توجد تقارير للتنزيل ضمن النتائج الحالية.');
  const files={},used=new Set();let pending;
  if(window.collectReportPDF)throw Error('يوجد تنزيل قيد التنفيذ.');
  window.collectReportPDF=(source,token,blob,record)=>{
    if(pending&&source===pending.frame.contentWindow&&token===pending.token)pending.resolve({blob,record});
  };
  try {
    for(const [i,entry] of entries.entries()) {
      status('جار تجهيز '+(i+1)+' من '+entries.length+': '+entry.title);
      const frame=document.createElement('iframe'),token=crypto.randomUUID();
      frame.name='report-download:'+token;frame.style.cssText='position:fixed;left:-10000px;width:1280px;height:900px';
      const url=new URL(entry.href,location.href);if(url.origin!==location.origin)throw Error('رابط تقرير غير صالح.');url.searchParams.set('action','pdf');
      let timer;
      try {
        const result=new Promise((resolve,reject)=>{pending={frame,token,resolve};timer=setTimeout(()=>reject(Error('تعذر تجهيز '+entry.title+'؛ لم يُنزّل ملف مضغوط ناقص. افتحي التقرير للتحقق ثم أعيدي المحاولة.')),120000);});
        frame.src=url.href;document.body.append(frame);
        const {blob,record}=await result;
        files[reportFilename({title:entry.title,id:entry.row?.id||record.id||entry.key},used)]=new Uint8Array(await blob.arrayBuffer());
      } finally {clearTimeout(timer);pending=null;frame.remove();}
    }
    const blob=new Blob([zip(files)],{type:'application/zip'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='تقارير أم كلثوم.zip';a.click();setTimeout(()=>URL.revokeObjectURL(url),30000);status('تم تجهيز '+entries.length+' تقريرًا بأسمائها داخل الملف المضغوط.');
  } finally {delete window.collectReportPDF;}
}
