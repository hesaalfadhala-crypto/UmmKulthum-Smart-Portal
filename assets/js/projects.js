import {meetingRPC} from './meeting-data.js?v=20261024-meetings';
import {fetchRecords,normalize,element} from './portal-data.js?v=20261024-meetings';
import {listBuildingDocumentations} from './building-documentation-data.js?v=20261023';
import {buildingDocHref} from './building-documentation-model.js?v=20261024-date';
const cards=[...document.querySelectorAll('.project')],search=document.querySelector('.search');let loading=false;
search.addEventListener('input',()=>cards.forEach(card=>card.hidden=!card.querySelector('h3').textContent.toLowerCase().includes(search.value.trim().toLowerCase())));
async function load(){if(loading)return;loading=true;try{
 const [general,building,meeting]=await Promise.allSettled([fetchRecords(),listBuildingDocumentations(),meetingRPC('list')]);const meetingRows=meeting.status==='fulfilled'?meeting.value:[];const rows=general.status==='fulfilled'?general.value:[],buildingRows=building.status==='fulfilled'?building.value:[];let linked=0;
 document.querySelector('.summary .stat:first-child strong').textContent=cards.length;
 for(const card of cards){card.querySelector('.project-report-list')?.remove();const name=card.querySelector('h3').textContent.trim(),isBuilding=card.id==='building-followup-project',matching=isBuilding?buildingRows:rows.filter(row=>(normalize(row).data.projects.includes(name)||row.activity_type==='اجتماع'&&meetingRows.some(m=>String(m.document.id)===String(row.id)&&m.links.some(t=>t.kind==='project'&&t.name===name))));
  card.querySelector('.project-footer span:last-child').textContent=matching.length;card.querySelector('.status').textContent=(isBuilding?building:general).status==='rejected'?'تعذر التحميل؛ أعيدي تحديث الصفحة':matching.length?'توثيقات محفوظة':'لا توجد توثيقات ضمن صلاحياتكِ';
  if(matching.length){const list=element('div');list.className='project-report-list';for(const row of matching.filter(r=>isBuilding||r.activity_type!=='اجتماع')){const link=element('a',isBuilding?row.title:normalize(row).data.activity);link.href=isBuilding?buildingDocHref(row.id):'report.html?id='+encodeURIComponent(String(row.id));link.style.display='block';list.append(link);if(isBuilding){list.append(element('p','اسم المعلمة: '+row.teacher_name+' — معدّة التقرير: '+row.author_name));for(const [label,action]of [['طباعة التقرير','print'],['تنزيل PDF','pdf']]){const a=element('a',label);a.href=buildingDocHref(row.id,action);a.style.marginInlineEnd='12px';list.append(a);}}}card.append(list);}
 }
 linked=rows.filter(row=>normalize(row).data.projects.some(name=>cards.some(c=>c.querySelector('h3').textContent.trim()===name))).length+buildingRows.length;
 document.querySelector('.summary .stat:nth-child(2) strong').textContent=linked;
}catch(error){document.querySelector('.heading').append(element('p',error.message));}finally{loading=false;}}
window.addEventListener('pageshow',event=>{if(event.persisted)void load();});window.addEventListener('focus',()=>void load());void load();
