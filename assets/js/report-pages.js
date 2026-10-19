import {drawSignatures} from './report-signatures.js?v=20261017-compact-supervision';
import {extraSections} from './recognition-model.js?v=20261017-edit-complete';
import {packPDF} from './pdf-export.js?v=20261017-compact-supervision';
export const PAGE_MODES=['auto','one','two'];
const W=1240,H=1754,M=65,BOTTOM=1600;
const overflow=()=>new Error('لا يتسع المحتوى في التنسيق المختار بصورة مقروءة. اختاري صفحتين أو قلّلي الصور أو النصوص. لم يُحذف أي محتوى.');
function wrap(g,value,width){const lines=[];for(const para of String(value).split('\n')){let line='';for(const word of para.split(/\s+/)){let part='';for(const ch of word){if(part&&g.measureText(part+ch).width>width){if(line){lines.push(line);line='';}lines.push(part);part=ch;}else part+=ch;}const next=line?line+' '+part:part;if(line&&g.measureText(next).width>width){lines.push(line);line=part;}else line=next;}lines.push(line);}return lines;}
export function reportCanvases(record,mode='auto',{createCanvas,logo,photos=[]}){
 if(!PAGE_MODES.includes(mode))throw Error('تنسيق الصفحات غير صالح.');
 const d=record.data;
 const fields=[['المرفقات',(record.attachment_files||[]).map(f=>f.name)],['النوع / القسم',[d.type,d.department]],['المنفذة / التاريخ',[d.executor,d.date,d.location]],['المجالات',d.areas],['المشاريع والمبادرات',d.projects],['اللجان',d.committees],['الفئات المستهدفة',[...(d.targets||[]),d.target].filter(Boolean)],['الهدف',d.goal],['وصف التنفيذ',d.implementation],['النتائج والأثر',d.impact],['التوصيات',d.recommendations]];
 fields.push(...extraSections(d));
 if(d.type==='ورشة تدريبية'&&!d.executionScope){fields.push(['نوع الورشة',d.workshopType==='external'?'خارجية':d.workshopType==='internal'?'داخلية':'غير مسجل'],['الجهة المنفذة',d.executingAgency]);}if(d.type==='ورشة تدريبية')fields.push(['المشاركات الفعلية',d.trainingBeneficiaries==null||d.trainingBeneficiaries===''?'غير مسجلة':String(d.trainingBeneficiaries)]);
 if(d.type==='مسابقة وإنجاز طلابي')fields.push(...[['اسم المسابقة',d.docCompetitionName],['نوع المسابقة',d.docCompetitionType],['الجهة المنظمة',d.docCompetitionOrganizer],['الجهة المستضيفة',d.docCompetitionHost],['المستوى',d.docCompetitionLevel],['الطالبات المشاركات',d.docCompetitionStudents],['النتيجة / المركز',d.docCompetitionResult],['تفاصيل الإنجاز',d.docCompetitionDetails]]);
 if(d.type==='حصة احتياط')fields.push(...[['الصف / الشعبة',d.reserveClass],['رقم الحصة',d.reservePeriod],['المعلمة الغائبة',d.originalTeacher],['ما تم تنفيذه',d.reserveImplementation]]);

 const measure=createCanvas(W,H).getContext('2d');
 const size=26,lh=40,font='"Portal Arabic", Tahoma, Arial';measure.font=size+'px '+font;
 const blocks=[];
 const addText=(value,bold=false)=>{measure.font=(bold?'bold ':'')+size+'px '+font;for(const text of wrap(measure,value,W-2*M))blocks.push({height:lh,text,bold});};
 addText('يوثّق هذا التقرير النشاط المدرسي وأهدافه وتنفيذه ونتائجه وأثره.');
 for(const [label,value]of fields){const s=Array.isArray(value)?value.filter(Boolean).join(' • '):value;if(!s)continue;addText(label+' : '+s);blocks.push({height:12});}
 if(photos.length){addText('صور التوثيق',true);for(let i=0;i<photos.length;i+=2)blocks.push({height:284,images:photos.slice(i,i+2),offset:i});}
 measure.font='bold 30px '+font;
 const titleLines=wrap(measure,'تقرير '+d.type+' — '+d.activity,W-2*M);
 const top=190+titleLines.length*42+48;
 const signatureHeight=drawSignatures(measure,d,W,M,0,size,font,false)+30;
 const total=blocks.reduce((n,b)=>n+b.height,0),oneCap=BOTTOM-top-signatureHeight;
 let count=mode==='two'?2:total<=oneCap?1:2;if(mode==='one'&&total>oneCap)throw overflow();
 const cap1=BOTTOM-top,cap2=BOTTOM-top-signatureHeight;
 if(top>600||total>(count===1?oneCap:cap1+cap2))throw overflow();
 let pages=[blocks];
 if(count===2){let best=null,score=Infinity,used=0;for(let i=1;i<blocks.length;i++){used+=blocks[i-1].height;const rest=total-used;if(used>cap1||rest>cap2||blocks[i-1].bold||!rest)continue;const diff=Math.abs(used-rest);if(diff<score){best=i;score=diff;}}if(best===null)throw overflow();pages=[blocks.slice(0,best),blocks.slice(best)];}
 return pages.map((items,page)=>{const c=createCanvas(W,H),g=c.getContext('2d');g.fillStyle='white';g.fillRect(0,0,W,H);g.direction='rtl';g.textAlign='right';
 const scale=Math.min((W-2*M)/logo.width,115/logo.height);g.drawImage(logo,(W-logo.width*scale)/2,30,logo.width*scale,logo.height*scale);
 g.fillStyle='#174f4b';g.font='bold 30px '+font;let ty=190;for(const line of titleLines){g.fillText(line,W-M,ty);ty+=42;}g.font='24px '+font;g.fillText('العام الدراسي '+(d.academicYear||'غير مسجل')+' · '+(d.semester||''),W-M,ty+8);
 let y=top;for(const b of items){if(b.text!==undefined){g.fillStyle=b.bold?'#174f4b':'#263d39';g.font=(b.bold?'bold ':'')+size+'px '+font;g.fillText(b.text,W-M,y+size);}if(b.images){const gap=20,bw=(W-2*M-gap)/2,bh=250;b.images.forEach((im,i)=>{const x=W-M-bw-i*(bw+gap);g.fillStyle='#f2f5f3';g.fillRect(x,y,bw,bh);const r=Math.min(bw/im.width,bh/im.height);g.drawImage(im,x+(bw-im.width*r)/2,y+(bh-im.height*r)/2,im.width*r,im.height*r);g.fillStyle='#637772';g.font='20px '+font;g.fillText('الصورة '+(b.offset+i+1),x+bw,y+bh+24);});}y+=b.height;}
 if(page===pages.length-1)drawSignatures(g,d,W,M,BOTTOM-signatureHeight+15,size,font,true);
 g.fillStyle='#637772';g.font='20px '+font;g.textAlign='right';g.fillText('بوابة أم كلثوم الذكية · رقم التوثيق '+String(record.id),W-M,1680);g.textAlign='left';g.fillText('صفحة '+(page+1)+' من '+pages.length,M,1680);return c;});
}
async function image(url){const response=await fetch(url,{cache:'no-store'});if(!response.ok)throw Error('تعذر تحميل صورة؛ أعيدي المحاولة قبل الطباعة.');const u=URL.createObjectURL(await response.blob());try{const im=new Image();im.src=u;await im.decode();return im;}finally{URL.revokeObjectURL(u);}}
export async function prepareReport(record,mode){await document.fonts.load('26px "Portal Arabic"');await document.fonts.load('bold 26px "Portal Arabic"');await document.fonts.ready;const [logo,...photos]=await Promise.all([image('school-logo.png'),...record.photos.map(p=>image(p.url))]);return reportCanvases(record,mode,{logo,photos,createCanvas:(w,h)=>Object.assign(document.createElement('canvas'),{width:w,height:h})});}
export function reportPDF(pages){return packPDF(pages.map(c=>Uint8Array.from(atob(c.toDataURL('image/jpeg',.96).split(',')[1]),c=>c.charCodeAt(0))));}
export async function outputReport(record,mode,print=false){const pages=await prepareReport(record,mode);if(!print){const u=URL.createObjectURL(new Blob([reportPDF(pages)],{type:'application/pdf'})),a=document.createElement('a');a.href=u;a.download='تقرير-'+record.id+'.pdf';a.click();setTimeout(()=>URL.revokeObjectURL(u),30000);return;}
 const frame=document.createElement('iframe');frame.title='طباعة التقرير';frame.style.cssText='position:fixed;width:1px;height:1px;left:-10000px';document.body.append(frame);const doc=frame.contentDocument;doc.open();doc.write('<!doctype html><html dir="rtl"><head><title>طباعة التقرير</title><style>@page{size:A4 portrait;margin:0}html,body{margin:0;padding:0}.page{width:210mm;height:297mm;box-sizing:border-box;break-after:page;page-break-after:always}.page:last-child{break-after:auto;page-break-after:auto}.page img{display:block;width:100%;height:100%}</style></head><body></body></html>');doc.close();for(const c of pages){const div=doc.createElement('div'),img=doc.createElement('img');div.className='page';img.src=c.toDataURL('image/png');div.append(img);doc.body.append(div);}await Promise.all([...doc.images].map(im=>im.decode()));frame.contentWindow.addEventListener('afterprint',()=>frame.remove(),{once:true});frame.contentWindow.focus();frame.contentWindow.print();}
