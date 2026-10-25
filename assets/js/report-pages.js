import {appendAttachments} from './pdf-attachments.js?v=20261023-embedded';
import {attachmentCanvases} from './pdf-attachment-preview.js?v=20261025-flow';
import {ensureReportFonts} from './report-fonts.js?v=20261019-cairo';
import {drawSignatures} from './report-signatures.js?v=20261021-spacing';
import {extraSections,isRecognition,reportFields} from './recognition-model.js?v=20261021-unified';
import {packPDF} from './pdf-export.js?v=20261021-spacing';
// Canvas pixels scale to A4 at 0.48 pt/px: 14px ≈ 6.7pt; 12px ≈ 5.8pt; 22px ≈ 10.6pt.
export const REPORT_SPACING=Object.freeze({lineHeight:1.4,paragraph:6,heading:6,section:12});
export const PAGE_MODES=['auto','one','two'];
const W=1240,H=1754,M=65,BOTTOM=1600;
const overflow=()=>new Error('تعذر توزيع أحد عناصر التقرير دون قص. لم يُحذف أي محتوى.');
function wrap(g,value,width){const lines=[];for(const para of String(value).split('\n')){let line='';for(const word of para.split(/\s+/)){let part='';for(const ch of word){if(part&&g.measureText(part+ch).width>width){if(line){lines.push(line);line='';}lines.push(part);part=ch;}else part+=ch;}const next=line?line+' '+part:part;if(line&&g.measureText(next).width>width){lines.push(line);line=part;}else line=next;}lines.push(line);}return lines;}
export function reportCanvases(record,mode='auto',{createCanvas,logo,photos=[]}){
 if(!PAGE_MODES.includes(mode))throw Error('تنسيق الصفحات غير صالح.');
 const d=record.data;
 const fields=[['المرفقات',(record.attachment_files||[]).map(f=>f.name)],...(isRecognition(d)?reportFields(d):[['النوع / القسم',[d.type,d.department]],['المنفذة / التاريخ',[d.executor,d.date,d.location]],...reportFields(d)])];
 if(!isRecognition(d)&&d.type==='ورشة تدريبية'&&!d.executionScope){fields.push(['نوع الورشة',d.workshopType==='external'?'خارجية':d.workshopType==='internal'?'داخلية':''],['الجهة المنفذة',d.executingAgency]);}if(!isRecognition(d)&&d.type==='ورشة تدريبية')fields.push(['المشاركات الفعلية',d.trainingBeneficiaries==null||d.trainingBeneficiaries===''?'':String(d.trainingBeneficiaries)]);
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

 for(const [label,value]of fields){const s=Array.isArray(value)?value.filter(Boolean).join(' • '):value;if(s==null||!String(s).trim())continue;heading(label);addText(s);space(REPORT_SPACING.section);}
 if(photos.length){heading('صور التوثيق');const layout=record.photoLayout||'auto';for(let i=0;i<photos.length;){const im=photos[i],wide=im.width/im.height>=1.9,single=layout==='large'||photos.length-i===1||wide||(photos[i+1]&&photos[i+1].width/photos[i+1].height>=1.9);const columns=single?1:2,images=photos.slice(i,i+columns),bh=single?520:410;blocks.push({height:bh+48,images,offset:i,columns,imageHeight:bh});i+=columns;}}
 measure.font='bold 36px '+font;
 const titleLines=wrap(measure,isRecognition(d)?d.activity:'تقرير '+(d.reportTypeLabel||d.type)+' — '+d.activity,W-2*M);
 const top=190+titleLines.length*42+24;
 const signatureHeight=drawSignatures(measure,d,W,M,0,size,font,false)+30;
 // Flow at readable sizes, with no page-count ceiling. Keep headings with the first content lines.
 while(blocks.at(-1)?.space)blocks.pop();if(blocks.length)blocks.at(-1).keepWithNext=true;
 blocks.push({height:signatureHeight,signature:true});
 const pages=[];let items=[],used=0;
 const pageTop=index=>index===0?top:125;
 const flush=()=>{while(items.at(-1)?.space)items.pop();if(items.length)pages.push(items);items=[];used=0;};
 for(let i=0;i<blocks.length;){const group=[];let h=0;do{const block=blocks[i++];group.push(block);h+=block.height;if(!block.keepWithNext)break;}while(i<blocks.length);
 if(group.every(b=>b.space)&&!items.length)continue;
 if(h>BOTTOM-pageTop(pages.length)-used&&items.length)flush();
 if(h>BOTTOM-pageTop(pages.length))throw overflow();
 for(const b of group){if(!items.length&&b.space)continue;items.push(b);used+=b.height;}}
 flush();
 return pages.map((items,page)=>{const c=createCanvas(W,H),g=c.getContext('2d');g.fillStyle='white';g.fillRect(0,0,W,H);g.direction='rtl';g.textAlign='right';
 if(page===0){const scale=Math.min((W-2*M)/logo.width,115/logo.height);g.drawImage(logo,(W-logo.width*scale)/2,30,logo.width*scale,logo.height*scale);
 g.fillStyle='#18574D';g.font='bold 36px '+font;let ty=190;for(const line of titleLines){g.fillText(line,W-M,ty);ty+=42;}g.font='24px '+font;g.fillStyle='#000000';g.fillText('العام الدراسي '+(d.academicYear||'غير مسجل')+' · '+(d.semester||''),W-M,ty+8);
 }else{g.fillStyle='#18574D';g.font='bold 26px '+font;g.fillText('تقرير التوثيق — تابع',W-M,75);}
 let y=pageTop(page);for(const b of items){if(b.text!==undefined){g.fillStyle=b.bold?'#18574D':'#000000';g.font=(b.bold?'bold ':'')+(b.bold?26:size)+'px '+font;if(b.bullet){g.beginPath();g.arc(W-M-7,y+size*.65,3,0,Math.PI*2);g.fill();}g.fillText(b.text,W-M-(b.indent||0),y+size);}if(b.images){const gap=20,columns=b.columns||2,bw=(W-2*M-gap*(columns-1))/columns,bh=b.imageHeight;b.images.forEach((im,i)=>{const x=W-M-bw-i*(bw+gap);g.fillStyle='#f2f5f3';g.fillRect(x,y,bw,bh);const r=Math.min(bw/im.width,bh/im.height);g.drawImage(im,x+(bw-im.width*r)/2,y+(bh-im.height*r)/2,im.width*r,im.height*r);g.fillStyle='#000000';g.font='20px '+font;g.fillText('الصورة '+(b.offset+i+1),x+bw,y+bh+24);});}if(b.signature)drawSignatures(g,d,W,M,y+10,size,font,true);y+=b.height;}

 g.fillStyle='#000000';g.font='20px '+font;g.textAlign='right';g.fillText('بوابة أم كلثوم الذكية · رقم التوثيق '+String(record.id),W-M,1680);g.textAlign='left';g.fillText('صفحة '+(page+1)+' من '+pages.length,M,1680);return c;});
}
async function image(url){const response=await fetch(url,{cache:'no-store'});if(!response.ok)throw Error('تعذر تحميل صورة؛ أعيدي المحاولة قبل الطباعة.');const u=URL.createObjectURL(await response.blob());try{const im=new Image();im.src=u;await im.decode();return im;}finally{URL.revokeObjectURL(u);}}
export async function prepareReport(record,mode){await ensureReportFonts();await document.fonts.load('26px "Cairo"');await document.fonts.load('bold 26px "Cairo"');await document.fonts.ready;const [logo,...photos]=await Promise.all([image('school-logo.png'),...record.photos.map(p=>image(p.url))]);return reportCanvases(record,mode,{logo,photos,createCanvas:(w,h)=>{const c=Object.assign(document.createElement('canvas'),{width:w*2,height:h*2});c.getContext('2d').scale(2,2);return c;}});}
export function reportPDF(pages){return packPDF(pages.map(c=>Uint8Array.from(atob(c.toDataURL('image/jpeg',.96).split(',')[1]),c=>c.charCodeAt(0))),pages[0]?.width||W,pages[0]?.height||H);}
export async function outputReport(record,mode,print=false,{includeAttachments=true}={}){const reportPages=await prepareReport(record,mode),attached=includeAttachments?(record.attachment_files||[]):[];if(!print){const bytes=await appendAttachments(reportPDF(reportPages),attached);const u=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'})),a=document.createElement('a');a.href=u;a.download='تقرير-'+record.id+'.pdf';a.click();setTimeout(()=>URL.revokeObjectURL(u),30000);return;}
 const pages=[...reportPages,...await attachmentCanvases(attached)];
 const frame=document.createElement('iframe');frame.title='طباعة التقرير';frame.style.cssText='position:fixed;width:1px;height:1px;left:-10000px';document.body.append(frame);const doc=frame.contentDocument;doc.open();doc.write('<!doctype html><html dir="rtl"><head><title>طباعة التقرير</title><style>@page{size:A4 portrait;margin:0}@page landscapePage{size:A4 landscape;margin:0}html,body{margin:0;padding:0}.page{width:210mm;height:297mm;box-sizing:border-box;break-after:page;page-break-after:always}.page:last-child{break-after:auto;page-break-after:auto}.page img{display:block;width:100%;height:100%;object-fit:contain;background:white}</style></head><body></body></html>');doc.close();for(const c of pages){const div=doc.createElement('div'),img=doc.createElement('img');div.className='page';if(c.width>c.height){div.style.width='297mm';div.style.height='210mm';div.style.page='landscapePage';}img.src=c.toDataURL('image/png');div.append(img);doc.body.append(div);}await Promise.all([...doc.images].map(im=>im.decode()));frame.contentWindow.addEventListener('afterprint',()=>frame.remove(),{once:true});frame.contentWindow.focus();frame.contentWindow.print();}

