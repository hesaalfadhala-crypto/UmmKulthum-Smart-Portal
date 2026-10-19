import {ensureReportFonts} from './report-fonts.js?v=20261019-cairo';
import {drawSignatures} from './report-signatures.js?v=20261019-cairo';
import {appendAttachments} from './pdf-attachments.js?v=20261017-edit-complete';
import {extraSections} from './recognition-model.js?v=20261017-edit-complete';
import {packPDF} from './pdf-export.js?v=20261019-cairo';
async function image(url){const r=await fetch(url,{cache:'no-store'});if(!r.ok)throw new Error('تعذر تحميل صور التقرير. أعيدي المحاولة.');const src=URL.createObjectURL(await r.blob());try{const img=new Image();await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(new Error('تعذر قراءة صورة التقرير.'));img.src=src;});return img;}finally{URL.revokeObjectURL(src);}}
export async function renderOnePagePDF(record){await ensureReportFonts();
 await document.fonts.ready;
 if(document.fonts.load)await Promise.all([document.fonts.load('20px "Cairo"'),document.fonts.load('bold 20px "Cairo"')]);
 const d=record.data,logo=await image('school-logo.png'),photos=await Promise.all(record.photos.map(p=>image(p.url)));
 const W=1240,H=1754,M=64,MAX=1590,c=document.createElement('canvas');c.width=W;c.height=H;const g=c.getContext('2d');
 const fields=[['المرفقات',(record.attachment_files||[]).map(f=>f.name)],['النوع / القسم',[d.type,d.department]],['المنفذة / التاريخ',[d.executor,d.date,d.location]],['المجالات',d.areas],['المشاريع والمبادرات',d.projects],['اللجان',d.committees],['الفئات المستهدفة',[...(d.targets||[]),d.target].filter(Boolean)],['الهدف',d.goal],['وصف التنفيذ',d.implementation],['النتائج والأثر',d.impact],['التوصيات',d.recommendations]];
 fields.push(...extraSections(d).filter(([label])=>!['آخر تعديل','عدّلته'].includes(label)));
 if(d.type==='ورشة تدريبية'&&!d.executionScope){fields.push(['نوع الورشة',d.workshopType==='external'?'خارجية':d.workshopType==='internal'?'داخلية':'غير مسجل'],['الجهة المنفذة',d.executingAgency]);}if(d.type==='ورشة تدريبية')fields.push(['المشاركات الفعلية',d.trainingBeneficiaries==null||d.trainingBeneficiaries===''?'غير مسجلة':String(d.trainingBeneficiaries)]);
 if(d.type==='مسابقة وإنجاز طلابي')fields.push(...[['اسم المسابقة',d.docCompetitionName],['نوع المسابقة',d.docCompetitionType],['الجهة المنظمة',d.docCompetitionOrganizer],['الجهة المستضيفة',d.docCompetitionHost],['المستوى',d.docCompetitionLevel],['الطالبات المشاركات',d.docCompetitionStudents],['النتيجة / المركز',d.docCompetitionResult],['تفاصيل الإنجاز',d.docCompetitionDetails]]);
 if(d.type==='حصة احتياط')fields.push(...[['الصف / الشعبة',d.reserveClass],['رقم الحصة',d.reservePeriod],['المعلمة الغائبة',d.originalTeacher],['ما تم تنفيذه',d.reserveImplementation]]);
 function fitText(value,width){const lines=[];for(const p of String(value).split('\n')){let line='';for(const word of p.split(/\s+/)){let chunks=[],part='';for(const letter of word){if(part&&g.measureText(part+letter).width>width){chunks.push(part);part=letter;}else part+=letter;}chunks.push(part);for(const chunk of chunks){const next=line?line+' '+chunk:chunk;if(line&&g.measureText(next).width>width){lines.push(line);line=chunk;}else line=next;}}lines.push(line);}return lines;}
 function layout(size,draw){const lh=size*1.48;let y=50;g.direction='rtl';g.textAlign='right';
  const text=(value,x,width,font=size,color='#000000',bold=false)=>{g.font=(bold?'bold ':'')+font+'px "Cairo", Tahoma, Arial';const lines=fitText(value,width);if(draw){g.fillStyle=color;for(let i=0;i<lines.length;i++)g.fillText(lines[i],x,y+i*font*1.48);}return lines.length*font*1.48;};
  const logoH=Math.min(125,(W-2*M)*logo.height/logo.width);if(draw){const scale=Math.min((W-2*M)/logo.width,logoH/logo.height);g.drawImage(logo,(W-logo.width*scale)/2,y,logo.width*scale,logo.height*scale);}y+=logoH+30;
  y+=text('تقرير '+d.type+' — '+d.activity,W-M,W-2*M,size+8,'#18574D',true)+8;
  y+=text('العام الدراسي '+(d.academicYear||'غير مسجل')+' · '+d.semester,W-M,W-2*M,size,'#000000')+8;
  y+=text('يوثّق هذا التقرير النشاط المدرسي وأهدافه وتنفيذه ونتائجه وأثره.',W-M,W-2*M,size,'#000000')+12;
  if(draw){g.fillStyle='#b59646';g.fillRect(M,y-6,W-2*M,2);}y+=size+10;
  for(const [label,value]of fields){const s=Array.isArray(value)?value.filter(Boolean).join(' • '):value;if(!s)continue;g.font=size+'px "Cairo", Tahoma, Arial';const ls=fitText(s,W-2*M-215);g.font='bold '+size+'px "Cairo", Tahoma, Arial';const labels=fitText(label,200);if(draw){g.fillStyle='#18574D';for(let i=0;i<labels.length;i++)g.fillText(labels[i],W-M,y+i*lh);g.font=size+'px "Cairo", Tahoma, Arial';g.fillStyle='#000000';for(let i=0;i<ls.length;i++)g.fillText(ls[i],W-M-215,y+i*lh);}y+=Math.max(ls.length,labels.length)*lh+9;}
  if(photos.length){y+=text('صور التوثيق',W-M,W-2*M,size,'#18574D',true)+6;const cols=photos.length>6?5:photos.length>2?3:photos.length,rows=Math.ceil(photos.length/cols),bw=(W-2*M-(cols-1)*12)/cols,bh=photos.length>6?140:photos.length>2?165:240;for(let i=0;i<photos.length;i++){const p=photos[i],x=W-M-bw-(i%cols)*(bw+12),top=y+Math.floor(i/cols)*(bh+25);if(draw){g.fillStyle='#f4f7f5';g.fillRect(x,top,bw,bh);const scale=Math.min(bw/p.width,bh/p.height);g.drawImage(p,x+(bw-p.width*scale)/2,top+(bh-p.height*scale)/2,p.width*scale,p.height*scale);g.fillStyle='#000000';g.font='16px "Cairo", Tahoma, Arial';g.fillText('الصورة '+(i+1),x+bw,top+bh+18);}}y+=rows*(bh+25)+16;}
  y+=18;const sh=drawSignatures(g,d,W,M,0,size,'"Cairo", Tahoma, Arial',false);if(draw)y=Math.max(y,MAX-sh);y+=drawSignatures(g,d,W,M,y,size,'"Cairo", Tahoma, Arial',draw);return y;
 }
 let size=25;for(;size>=16;size--)if(layout(size,false)<=MAX)break;
 if(size<16)throw new Error('النص أطول من مساحة صفحة واحدة بحجم مقروء. اختاري PDF الكامل لحفظ كل المحتوى.');
 g.fillStyle='#fff';g.fillRect(0,0,W,H);layout(size,true);g.strokeStyle='#dce5e3';g.beginPath();g.moveTo(M,1640);g.lineTo(W-M,1640);g.stroke();g.fillStyle='#000000';g.font='18px "Cairo", Tahoma, Arial';g.textAlign='right';g.fillText('بوابة أم كلثوم الذكية · رقم التوثيق '+String(record.id),W-M,1675);g.textAlign='left';g.fillText('صفحة 1 من 1',M,1675);
 return packPDF([Uint8Array.from(atob(c.toDataURL('image/jpeg',.96).split(',')[1]),x=>x.charCodeAt(0))]);
}
export async function exportOnePagePDF(record){const bytes=await appendAttachments(await renderOnePagePDF(record),record.attachment_files),url=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'})),a=document.createElement('a');a.href=url;a.download='تقرير-صفحة-واحدة-'+String(record.id)+'.pdf';a.click();setTimeout(()=>URL.revokeObjectURL(url),20000);}
