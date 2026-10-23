import {appendAttachments} from './pdf-attachments.js?v=20261023-embedded';
import {attachmentCanvases} from './pdf-attachment-preview.js?v=20261023-embedded';
import {ensureReportFonts} from './report-fonts.js?v=20261019-cairo';
import {drawSignatures} from './report-signatures.js?v=20261021-spacing';
import {extraSections,isRecognition,reportFields} from './recognition-model.js?v=20261021-unified';
import {packPDF} from './pdf-export.js?v=20261021-spacing';
// Canvas pixels scale to A4 at 0.48 pt/px: 14px ≈ 6.7pt; 12px ≈ 5.8pt; 22px ≈ 10.6pt.
export const REPORT_SPACING=Object.freeze({lineHeight:1.7,paragraph:14,heading:12,section:22});
export const PAGE_MODES=['auto','one','two'];
const W=1240,H=1754,M=65,BOTTOM=1600;
const overflow=()=>new Error('لا يتسع المحتوى في التنسيق المختار بصورة مقروءة. اختاري صفحتين أو قلّلي الصور أو النصوص. لم يُحذف أي محتوى.');
function wrap(g,value,width){const lines=[];for(const para of String(value).split('\n')){let line='';for(const word of para.split(/\s+/)){let part='';for(const ch of word){if(part&&g.measureText(part+ch).width>width){if(line){lines.push(line);line='';}lines.push(part);part=ch;}else part+=ch;}const next=line?line+' '+part:part;if(line&&g.measureText(next).width>width){lines.push(line);line=part;}else line=next;}lines.push(line);}return lines;}
export function reportCanvases(record,mode='auto',{createCanvas,logo,photos=[]}){
 if(!PAGE_MODES.includes(mode))throw Error('تنسيق الصفحات غير صالح.');
 const d=record.data;
 const fields=[['المرفقات',(record.attachment_files||[]).map(f=>f.name)],...(isRecognition(d)?reportFields(d):[['النوع / القسم',[d.type,d.department]],['المنفذة / التاريخ',[d.executor,d.date,d.location]],...reportFields(d)])];
 if(!isRecognition(d)&&d.type==='ورشة تدريبية'&&!d.executionScope){fields.push(['نوع الورشة',d.workshopType==='external'?'خارجية':d.workshopType==='internal'?'داخلية':'غير مسجل'],['الجهة المنفذة',d.executingAgency]);}if(!isRecognition(d)&&d.type==='ورشة تدريبية')fields.push(['المشاركات الفعلية',d.trainingBeneficiaries==null||d.trainingBeneficiaries===''?'غير مسجلة':String(d.trainingBeneficiaries)]);
 if(!isRecognition(d)&&d.type==='مسابقة وإنجاز طلابي')fields.push(...[['نوع التوثيق',d.reportTypeLabel||'مسابقة'],['اسم المسابقة أو الإنجاز',d.docCompetitionName],['المدرسة أو الجهة الخارجية',d.externalSchool],['نوع المسابقة',d.docCompetitionType],['الجهة المنظمة',d.docCompetitionOrganizer],['الجهة المستضيفة',d.docCompetitionHost],['المستوى',d.docCompetitionLevel],['الطالبات المشاركات',d.docCompetitionStudents],['النتيجة / المركز',d.docCompetitionResult],['تفاصيل الإنجاز',d.docCompetitionDetails]]);
 if(!isRecognition(d)&&d.type==='حصة احتياط')fields.push(...[['الصف / الشعبة',d.reserveClass],['رقم الحصة',d.reservePeriod],['المعلمة الغائبة',d.originalTeacher],['ما تم تنفيذه',d.reserveImplementation]]);

 const measure=createCanvas(W,H).getContext('2d');
 const size=24,lh=Math.ceil(size*REPORT_SPACING.lineHeight),font='"Cairo", Tahoma, Arial';measure.font=size+'px '+font;
 const blocks=[];
 const space=(height,keepWithNext=false)=>blocks.push({height,space:true,keepWithNext});
 const addText=(value,bold=false)=>{
  measure.font=(bold?'bold ':'')+(bold?26:size)+'px '+font;
  const paragraphs=String(value).replace(/\r\n?/g,'\n').split('\n');
  paragraphs.forEach((para,index)=>{
   if(index&&!bold)space(REPORT_SPACING.paragraph,true);
   const bullet=!bold&&para.match(/^\s*([•●▪-])\s+(.+)$/);
   const lines=wrap(measure,bullet?bullet[2]:para,W-2*M-(bullet?30:0));
   lines.forEach((text,i)=>blocks.push({height:bold?Math.ceil(26*REPORT_SPACING.lineHeight):lh,text,bold,indent:bullet?30:0,bullet:!!bullet&&i===0,keepWithNext:bold||i===0&&lines.length>1}));
  });
 };
 const heading=value=>{addText(value,true);space(REPORT_SPACING.heading,true);};
 if(!isRecognition(d)){addText('يوثّق هذا التقرير النشاط المدرسي وأهدافه وتنفيذه ونتائجه وأثره.');space(REPORT_SPACING.section);}
 for(const [label,value]of fields){const s=Array.isArray(value)?value.filter(Boolean).join(' • '):value;if(!s)continue;heading(label);addText(s);space(REPORT_SPACING.section);}
 if(photos.length){heading('صور التوثيق');const columns=2;for(let i=0;i<photos.length;i+=columns)blocks.push({height:272,images:photos.slice(i,i+columns),offset:i,columns});}
 measure.font='bold 36px '+font;
 const titleLines=wrap(measure,isRecognition(d)?d.activity:'تقرير '+(d.reportTypeLabel||d.type)+' — '+d.activity,W-2*M);
 const top=190+titleLines.length*42+48;
 const signatureHeight=drawSignatures(measure,d,W,M,0,size,font,false)+30;
 const prefix=[0];for(const b of blocks)prefix.push(prefix.at(-1)+b.height);
 const total=prefix.at(-1),oneCap=BOTTOM-top-signatureHeight,cap1=BOTTOM-top,cap2=BOTTOM-top-signatureHeight;
 const maxPages=record.allowExtraPage?3:2;
 function partition(count){
  if(count===1)return total<=oneCap?[blocks]:null;
  const target=(total+signatureHeight)/count;let best=null,bestScore=Infinity;
  function visit(start,page,parts,score){const last=page===count-1,capacity=last?cap2:cap1;
   if(last){const h=total-prefix[start];if(h<=0||h>capacity)return;const final=score+Math.abs(h+signatureHeight-target);if(final<bestScore){bestScore=final;best=[...parts,blocks.slice(start)];}return;}
   for(let end=start+1;end<blocks.length;end++){const h=prefix[end]-prefix[start];if(h>capacity)break;if(blocks[end-1].keepWithNext)continue;visit(end,page+1,[...parts,blocks.slice(start,end)],score+Math.abs(h-target));}
  }visit(0,0,[],0);return best;
 }
 let pages=null;if(top>600)throw overflow();
 if(mode==='one')pages=partition(1);else if(mode==='two')pages=partition(2);else for(let count=1;count<=maxPages&&!pages;count++)pages=partition(count);
 if(!pages)throw new Error(record.allowExtraPage?'لا يتسع المحتوى في التنسيق المختار بصورة مقروءة. يسمح التلقائي حتى ثلاث صفحات للمسابقات والإنجازات؛ قلّلي النصوص أو الصور عند الحاجة. لم يُحذف أي محتوى.':overflow().message);
 return pages.map((items,page)=>{const c=createCanvas(W,H),g=c.getContext('2d');g.fillStyle='white';g.fillRect(0,0,W,H);g.direction='rtl';g.textAlign='right';
 const scale=Math.min((W-2*M)/logo.width,115/logo.height);g.drawImage(logo,(W-logo.width*scale)/2,30,logo.width*scale,logo.height*scale);
 g.fillStyle='#18574D';g.font='bold 36px '+font;let ty=190;for(const line of titleLines){g.fillText(line,W-M,ty);ty+=42;}g.font='24px '+font;g.fillStyle='#000000';g.fillText('العام الدراسي '+(d.academicYear||'غير مسجل')+' · '+(d.semester||''),W-M,ty+8);
 let y=top;for(const b of items){if(b.text!==undefined){g.fillStyle=b.bold?'#18574D':'#000000';g.font=(b.bold?'bold ':'')+(b.bold?26:size)+'px '+font;if(b.bullet){g.beginPath();g.arc(W-M-7,y+size*.65,3,0,Math.PI*2);g.fill();}g.fillText(b.text,W-M-(b.indent||0),y+size);}if(b.images){const gap=20,columns=b.columns||2,bw=(W-2*M-gap*(columns-1))/columns,bh=220;b.images.forEach((im,i)=>{const x=W-M-bw-i*(bw+gap);g.fillStyle='#f2f5f3';g.fillRect(x,y,bw,bh);const r=Math.min(bw/im.width,bh/im.height);g.drawImage(im,x+(bw-im.width*r)/2,y+(bh-im.height*r)/2,im.width*r,im.height*r);g.fillStyle='#000000';g.font='20px '+font;g.fillText('الصورة '+(b.offset+i+1),x+bw,y+bh+24);});}y+=b.height;}
 if(page===pages.length-1)drawSignatures(g,d,W,M,y+20,size,font,true);
 g.fillStyle='#000000';g.font='20px '+font;g.textAlign='right';g.fillText('بوابة أم كلثوم الذكية · رقم التوثيق '+String(record.id),W-M,1680);g.textAlign='left';g.fillText('صفحة '+(page+1)+' من '+pages.length,M,1680);return c;});
}
async function image(url){const response=await fetch(url,{cache:'no-store'});if(!response.ok)throw Error('تعذر تحميل صورة؛ أعيدي المحاولة قبل الطباعة.');const u=URL.createObjectURL(await response.blob());try{const im=new Image();im.src=u;await im.decode();return im;}finally{URL.revokeObjectURL(u);}}
export async function prepareReport(record,mode){await ensureReportFonts();await document.fonts.load('26px "Cairo"');await document.fonts.load('bold 26px "Cairo"');await document.fonts.ready;const [logo,...photos]=await Promise.all([image('school-logo.png'),...record.photos.map(p=>image(p.url))]);return reportCanvases(record,mode,{logo,photos,createCanvas:(w,h)=>Object.assign(document.createElement('canvas'),{width:w,height:h})});}
export function reportPDF(pages){return packPDF(pages.map(c=>Uint8Array.from(atob(c.toDataURL('image/jpeg',.96).split(',')[1]),c=>c.charCodeAt(0))));}
export async function outputReport(record,mode,print=false){const reportPages=await prepareReport(record,mode);if(!print){const bytes=await appendAttachments(reportPDF(reportPages),record.attachment_files||[]);const u=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'})),a=document.createElement('a');a.href=u;a.download='تقرير-'+record.id+'.pdf';a.click();setTimeout(()=>URL.revokeObjectURL(u),30000);return;}
 const pages=[...reportPages,...await attachmentCanvases(record.attachment_files||[])];
 const frame=document.createElement('iframe');frame.title='طباعة التقرير';frame.style.cssText='position:fixed;width:1px;height:1px;left:-10000px';document.body.append(frame);const doc=frame.contentDocument;doc.open();doc.write('<!doctype html><html dir="rtl"><head><title>طباعة التقرير</title><style>@page{size:A4 portrait;margin:0}html,body{margin:0;padding:0}.page{width:210mm;height:297mm;box-sizing:border-box;break-after:page;page-break-after:always}.page:last-child{break-after:auto;page-break-after:auto}.page img{display:block;width:100%;height:100%;object-fit:contain;background:white}</style></head><body></body></html>');doc.close();for(const c of pages){const div=doc.createElement('div'),img=doc.createElement('img');div.className='page';img.src=c.toDataURL('image/png');div.append(img);doc.body.append(div);}await Promise.all([...doc.images].map(im=>im.decode()));frame.contentWindow.addEventListener('afterprint',()=>frame.remove(),{once:true});frame.contentWindow.focus();frame.contentWindow.print();}

