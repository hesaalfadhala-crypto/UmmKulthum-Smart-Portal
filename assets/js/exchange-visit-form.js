import {isExchange,CRITERIA,EXCHANGE_TYPE} from './exchange-visit-model.js';
import {renderExchange} from './exchange-visit-view.js';
const $=id=>document.getElementById(id);let catalog=null,owner=null,admin=false,active=false;
const inputIds=['exchangeLesson','exchangeSubject','exchangeClass','exchangeVisited','exchangeKind','exchangeVisitor','exchangePractices','exchangeCoordinator','exchangeFollowUp','academicYear'];
export function installExchange(){
 const option=[...$('type').options].find(o=>o.value==='زيارة');option.value=EXCHANGE_TYPE;option.textContent='زيارة صفية تبادلية';
 const box=document.createElement('section');box.id='exchangeFields';box.hidden=true;
 const field=(id,label,control)=>`<div class="field"><label for="${id}">${label}</label>${control}</div>`;
 const text=(id,label)=>field(id,label,`<input id="${id}" maxlength="300">`);
 const select=(id,label,values=[])=>field(id,label,`<select id="${id}"><option value="">اختاري</option>${values.map(v=>`<option>${v}</option>`).join('')}</select>`);
 box.innerHTML='<h3>بيانات الزيارة الصفية التبادلية</h3>'+text('academicYear','العام الدراسي')+text('exchangeLesson','عنوان الدرس')+text('exchangeSubject','المادة')+text('exchangeClass','الصف')+select('exchangeVisited','المعلمة المزارة')+select('exchangeKind','نوع الزيارة',['داخل القسم','خارج القسم'])+select('exchangeVisitor','المعلمة الزائرة')+'<h3>عناصر الدرس ومعايير الملاحظة</h3><table class="exchange-table"><thead><tr><th class="domain">عناصر الدرس</th><th>معايير الملاحظة</th><th class="mark">✓</th></tr></thead><tbody>'+CRITERIA.map(c=>`<tr><td>${c.domain}</td><td><label for="${c.id}">${c.text}</label></td><td class="mark"><input id="${c.id}" type="checkbox" data-exchange-criterion="${c.id}"></td></tr>`).join('')+'</tbody></table>'+field('exchangePractices','أبرز الممارسات المستفادة من الزيارة','<textarea id="exchangePractices" rows="4" maxlength="20000"></textarea>')+select('exchangeCoordinator','المعلمة الأولى أو المنسقة')+field('exchangeFollowUp','متابعة المديرة المساعدة','<textarea id="exchangeFollowUp" rows="3" maxlength="10000"></textarea>');
 $('trainingDocumentationFields').before(box);
 const preview=document.createElement('section');preview.id='exchangePreview';preview.hidden=true;document.querySelector('.report-title').after(preview);
 for(const id of ['exchangePractices','exchangeFollowUp'])$(id).addEventListener('input',()=>{const n=$(id);n.style.height='auto';n.style.height=n.scrollHeight+'px';});
}
export async function loadExchange(client,user){const {data,error}=await client.rpc('meeting_catalog');if(error)throw Error('تعذر تحميل أسماء المعلمات للزيارة التبادلية.');catalog=data;owner=user.id;admin=['principal','assistant_principal'].includes(data.profile.role);
 const staff=data.staff.filter(p=>p.user_id);for(const id of ['exchangeVisited','exchangeVisitor','exchangeCoordinator'])for(const p of staff){if(id==='exchangeCoordinator'&&!['first_teacher','coordinator','principal','assistant_principal'].includes(p.role)&&!/(أول|اول|منسق)/.test(p.job_title))continue;$(id).add(new Option(p.name,p.user_id));}
 $('exchangeVisitor').value=owner;
 const now=new Date(),parts=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bahrain',year:'numeric',month:'2-digit'}).formatToParts(now).map(p=>[p.type,p.value]));const y=Number(parts.year)-(Number(parts.month)<9?1:0);$('academicYear').value=`${y}-${y+1}`;
}
export function collectExchange(d){if(!isExchange(d))return d;
 const staff=catalog?.staff||[],visitor=staff.find(p=>p.user_id===$('exchangeVisitor').value),visited=staff.find(p=>p.user_id===$('exchangeVisited').value),coordinator=staff.find(p=>p.user_id===$('exchangeCoordinator').value);
 d.type=EXCHANGE_TYPE;d.projects=[];d.committees=[];d.areas=[];d.targets=[];delete d.recognition;d.exchangeVisit={schemaVersion:1,lessonTitle:$('exchangeLesson').value.trim(),subject:$('exchangeSubject').value.trim(),className:$('exchangeClass').value.trim(),kind:$('exchangeKind').value,visitedId:visited?.user_id||'',visitedName:visited?.name||'',visitorId:visitor?.user_id||owner,visitorName:visitor?.name||d.executor||'',coordinatorId:coordinator?.user_id||'',coordinatorName:coordinator?.name||'',selected:[...document.querySelectorAll('[data-exchange-criterion]:checked')].map(n=>n.dataset.exchangeCriterion),practices:$('exchangePractices').value.trim(),followUp:$('exchangeFollowUp').value.trim()};
 d.activity=d.exchangeVisit.lessonTitle;d.executor=d.exchangeVisit.visitorName;d.reportPreparedBy=d.executor;return d;
}
export function restoreExchange(d){if(!isExchange(d))return;const v=d.exchangeVisit||{};
 const values={exchangeLesson:v.lessonTitle||d.activity||'',exchangeSubject:v.subject||'',exchangeClass:v.className||'',exchangeVisited:v.visitedId||'',exchangeKind:v.kind||'',exchangeVisitor:v.visitorId||owner,exchangePractices:v.practices||d.implementation||'',exchangeCoordinator:v.coordinatorId||'',exchangeFollowUp:v.followUp||''};
 for(const [id,value]of Object.entries(values)){$(id).value=value;}
 document.querySelectorAll('[data-exchange-criterion]').forEach(n=>n.checked=(v.selected||[]).includes(n.dataset.exchangeCriterion));
 if(isExchange({type:$('type').value}))$('type').value=EXCHANGE_TYPE;
}
export function lockExchange(){if(active){if(!admin)$('exchangeVisitor').disabled=true;$('exchangeFollowUp').readOnly=!admin;}}
export function updateExchange(d){const on=isExchange(d),was=active;active=on;if(on&&!$('exchangeVisitor').value)$('exchangeVisitor').value=owner;if(on&&!$('academicYear').value){const y=new Date().getFullYear()-(new Date().getMonth()<8?1:0);$('academicYear').value=`${y}-${y+1}`;}$('exchangeFields').hidden=!on;$('exchangePreview').hidden=!on;
 const generic=['activity','executor','location','executingEntity','target','goal','implementation','impact','recommendations','reportPreparedBy'];
 for(const id of generic){if(on)$(id).closest('.field').hidden=true;else if(was)$(id).closest('.field').hidden=false;}
 for(const cls of ['area-checks','areas-checks','project-checks','committee-checks','target-checks']){const node=document.querySelector('.'+cls)?.closest('.field');if(node&&(on||was))node.hidden=on;}
 if(on){$('motivationFields').hidden=true;$('executionFields').hidden=true;$('recognitionFields').hidden=true;$('extensionPreview').hidden=true;}
 else if(was)$('extensionPreview').hidden=false;
 for(const id of inputIds)$(id).required=on&&!['exchangeCoordinator','exchangeFollowUp'].includes(id);
 $('date').required=on;lockExchange();
 const report=document.querySelector('article.report');for(const node of report.querySelectorAll('.report-meta,.report-section')){if(on)node.hidden=true;else if(was)node.hidden=false;}
 // The existing metadata grid and title are replaced by the dedicated tables.
 for(const id of ['pActivity','pSemester','pType','pDepartment','pExecutor','pDate','pLocation']){const n=$(id)?.parentElement;if(n&&(on||was))n.hidden=on;}
 if(on){document.querySelector('.report-title').hidden=true;renderExchange($('exchangePreview'),d);}else if(was)document.querySelector('.report-title').hidden=false;
}
