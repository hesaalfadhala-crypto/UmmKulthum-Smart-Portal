import {element,client} from './portal-data.js?v=20261017-edit-complete';
import {RECOGNITION_PROJECT,SCOPED_TYPES,RECOGNITION_KINDS,AWARDS,extraSections,RECOGNITION_TITLE,isRecognition} from './recognition-model.js?v=20261021-recognition';
const $=id=>document.getElementById(id);let staff=[],allowed=false,wasRecognition=false;
export function installExtensions(){
 const type=$('type');if(![...type.options].some(o=>o.value==='ملتقى'))type.add(new Option('ملتقى','ملتقى'));
 const project=element('label',undefined,'check');project.append(Object.assign(element('input'),{type:'checkbox',value:RECOGNITION_PROJECT}),document.createTextNode(RECOGNITION_PROJECT));project.id='recognitionProjectOption';project.hidden=true;document.querySelector('.project-checks').append(project);
 const field=(id,label,type='text')=>`<div class="field"><label for="${id}">${label}</label>${['recognitionReason','recognitionNotes'].includes(id)?`<textarea id="${id}" maxlength="6000" rows="3"></textarea>`:`<input id="${id}" type="${type}" maxlength="300">`}</div>`;
 const box=element('div');box.innerHTML=`<section id="executionFields" hidden><fieldset style="border:0;padding:0;margin:0"><legend>نطاق التنفيذ *</legend><div class="checks"><label class="check"><input type="radio" name="executionScopeChoice" value="internal"> داخلية</label><label class="check"><input type="radio" name="executionScopeChoice" value="external"> خارجية</label></div><select id="executionScope" hidden aria-hidden="true" tabindex="-1"><option value="">اختاري</option><option value="internal">داخلية</option><option value="external">خارجية</option></select></fieldset><div id="externalFields" hidden>${field('organizingEntity','الجهة المنظمة *')}${field('hostingEntity','الجهة المستضيفة *')}</div></section><section id="recognitionFields" hidden><h3>${RECOGNITION_PROJECT}</h3><p>توثيق تكريم المعلمات والإداريات تقديرًا لجهودهن ومبادراتهن وإنجازاتهن.</p>${field('recognitionTitle','عنوان التقرير *')}${field('recognitionDate','تاريخ التكريم *','date')}<fieldset><legend>المكرمات والأقسام — اختاري اسمًا أو أكثر *</legend><input id="staffSearch" type="search" placeholder="بحث بالاسم أو القسم"><div id="recognitionStaff" style="max-height:260px;overflow:auto"></div></fieldset><div class="field" hidden><label for="recognitionKind">نوع التكريم *</label><select id="recognitionKind"><option value="">اختاري</option>${RECOGNITION_KINDS.map(v=>`<option>${v}</option>`).join('')}</select></div><div id="kindOtherField" hidden>${field('recognitionKindOther','يرجى التحديد')}</div><div hidden>${field('recognitionReason','سبب تكريم مشترك')}${field('recognitionHours','ساعات مشتركة','number')}</div><div id="recipientDetails"></div><fieldset><legend>نوع التكريم — يمكن اختيار أكثر من خيار *</legend><div id="recognitionAwards">${AWARDS.map(v=>`<label ${['تكريم في اجتماع أو فعالية','هدية رمزية'].includes(v)?'hidden':''}><input type="checkbox" value="${v}">${v==='شهادة شكر وتقدير'?'شهادة شكر':v==='بطاقة شكر إلكترونية'?'بطاقة شكر':v}</label>`).join('<br>')}</div></fieldset><div id="awardOtherField" hidden>${field('recognitionAwardOther','يرجى التحديد')}</div><div id="hoursField" hidden><p>أدخلي ساعات السعادة في بطاقة كل مكرمة؛ يمكن أن تختلف الساعات.</p></div><div hidden>${field('recognitionPresenter','الجهة المقدمة للتكريم')}</div>${field('recognitionNotes','ملاحظات إضافية (اختياري)')}<p>أرفقي الصور في صور التوثيق والشهادات والمستندات في مرفقات PDF أدناه.</p><a href="recognition.html">لوحة إحصاءات التكريم</a></section>`;
 $('trainingDocumentationFields').before(box);$('location').closest('.field').after($('executionFields'));
 document.querySelectorAll('[name=executionScopeChoice]').forEach(input=>input.addEventListener('change',()=>{$('executionScope').value=input.value;$('executionScope').dispatchEvent(new window.Event('input',{bubbles:true}));}));$('recognitionHours').min='0.01';$('recognitionHours').max='1000';$('recognitionHours').step='0.01';
 // Legacy workshop fields remain in drafts, but the common scope is the only editable control.
 $('workshopType').closest('.field').hidden=true;$('agencyField').hidden=true;
 const preview=element('section');preview.id='extensionPreview';document.querySelector('.report-title').after(preview);
 $('staffSearch').addEventListener('input',()=>{const q=$('staffSearch').value.trim();[...$('recognitionStaff').children].forEach(l=>l.hidden=!l.textContent.includes(q));});
}
function recipientEditors(r={}){
 const selected=new Set([...$('recognitionStaff').querySelectorAll('input:checked')].map(i=>i.value));
 for(const card of [...$('recipientDetails').children])if(!selected.has(card.dataset.id))card.remove();
 for(const p of staff.filter(p=>selected.has(p.id))){
  if([...$('recipientDetails').children].some(c=>c.dataset.id===p.id))continue;
  const old=(r.recipients||[]).find(x=>x.id===p.id)||{};
  const card=element('fieldset');card.dataset.id=p.id;card.className='recognition-recipient';
  const legend=element('legend',p.full_name+(p.department?' — '+p.department:''));
  const reason=element('textarea');reason.dataset.recipientReason=p.id;reason.maxLength=6000;reason.rows=2;reason.value=old.reason||r.reason||'';reason.setAttribute('aria-label','سبب تكريم '+p.full_name);
  const reasonLabel=element('label','سبب التكريم أو الشكر *');reasonLabel.append(reason);
  const hours=element('input');hours.dataset.recipientHours=p.id;hours.type='number';hours.min='.01';hours.max='1000';hours.step='.01';hours.value=old.hours??r.hours??'';hours.setAttribute('aria-label','ساعات السعادة — '+p.full_name);
  const hoursLabel=element('label','عدد ساعات السعادة *');hoursLabel.dataset.hoursLabel='';hoursLabel.append(hours);
  card.append(legend,reasonLabel,hoursLabel);$('recipientDetails').append(card);
 }
}
export async function loadExtensionAccess(){const {data,error}=await client.rpc('recognition_context');if(error)throw new Error('تعذر التحقق من صلاحيات التكريم.');allowed=!!data.can_write;$('recognitionProjectOption').hidden=!allowed;if(allowed){const r=await client.rpc('recognition_staff');if(r.error)throw new Error('تعذر تحميل أسماء الموظفات.');staff=r.data;for(const p of staff){const label=element('label');label.style.display='block';const input=element('input');input.type='checkbox';input.value=p.id;label.append(input,document.createTextNode(p.full_name+' — '+p.department));$('recognitionStaff').append(label);}}}
export function collectExtensions(d){
 const rec=d.projects.includes(RECOGNITION_PROJECT);const scoped=SCOPED_TYPES.includes(d.type);
 if(!scoped){d.executionScope='';d.organizingEntity='';d.hostingEntity='';}else if(rec){d.executionScope=d.executionScope||'internal';}else if(d.executionScope!=='external'){d.organizingEntity='';d.hostingEntity='';}
 if(d.type==='ورشة تدريبية'){d.workshopType=d.executionScope;d.executingAgency=d.organizingEntity;}
 if(!rec)delete d.recognition;
 if(rec){
  if(!d.type){d.type='فعالية';$('type').value=d.type;}
  if(!wasRecognition&&!d.recognitionTitle){$('recognitionTitle').value=RECOGNITION_TITLE;d.recognitionTitle=RECOGNITION_TITLE;}
  recipientEditors(d.recognition);
  const ids=[...$('recognitionStaff').querySelectorAll('input:checked')].map(i=>i.value);
  const awards=[...$('recognitionAwards').querySelectorAll('input:checked')].map(i=>i.value),happy=awards.includes('ساعات سعادة');
  const recipients=staff.filter(p=>ids.includes(p.id)).map(p=>{const card=[...$('recipientDetails').children].find(c=>c.dataset.id===p.id);return {id:p.id,name:p.full_name,department:p.department||'',reason:card.querySelector('textarea').value.trim(),hours:happy?Number(card.querySelector('input').value):0};});
  d.recognition={schemaVersion:2,title:d.recognitionTitle,date:d.recognitionDate,recipientIds:ids,recipients,kind:d.recognitionKind||'جهود استثنائية',kindOther:d.recognitionKindOther,reason:d.recognitionReason||'',awards,awardOther:d.recognitionAwardOther,hours:0,presenter:d.recognitionPresenter||d.reportPreparedBy||'',notes:d.recognitionNotes};
  d.activity=d.recognition.title;d.date=d.recognition.date;
 }
 return d;
}
export function updateExtensions(d){
 const rec=d.projects.includes(RECOGNITION_PROJECT),scoped=!rec&&SCOPED_TYPES.includes(d.type),external=scoped&&d.executionScope==='external';
 $('executionFields').hidden=!scoped;$('externalFields').hidden=!external;$('executionScope').required=scoped;
 document.querySelectorAll('[name=executionScopeChoice]').forEach(input=>{input.checked=input.value===d.executionScope;input.required=scoped;});
 for(const id of ['organizingEntity','hostingEntity']){$(id).required=external;if(!external&&!rec)$(id).value='';}
 $('workshopType').value=d.executionScope||'';$('executingAgency').value=d.organizingEntity||'';$('workshopType').required=false;$('executingAgency').required=false;
 $('recognitionFields').hidden=!rec;
 for(const id of ['recognitionTitle','recognitionDate'])$(id).required=rec;
 for(const id of ['recognitionKind','recognitionReason','recognitionPresenter','recognitionHours'])$(id).required=false;
 $('kindOtherField').hidden=true;$('recognitionKindOther').required=false;
 $('awardOtherField').hidden=!rec||!d.recognition?.awards?.includes('أخرى');$('recognitionAwardOther').required=!$('awardOtherField').hidden;
 const happy=rec&&d.recognition?.awards?.includes('ساعات سعادة');$('hoursField').hidden=!happy;
 for(const card of $('recipientDetails').children){card.querySelector('textarea').required=rec;card.querySelector('[data-hours-label]').hidden=!happy;card.querySelector('input').required=happy;}
 // Hide only presentation; preserve old values in the form, saved reports and other projects.
 for(const id of ['executingEntity','target','goal','implementation','impact','recommendations'])$(id).closest('.field').hidden=rec;
 document.querySelector('.target-checks').closest('.field').hidden=rec;
 const other=$('targetsOther');if(other){other.closest('.field').hidden=rec||!document.querySelector('.target-checks input[value="أخرى"]:checked');if(rec)other.required=false;}
 for(const id of ['pTarget','pGoal','pImplementation','pImpact','pRecommendations'])$(id).closest('.report-section').hidden=rec;
 for(const id of ['activity','date','executor','location','type','department'])$(id).closest('.field').hidden=rec;
 for(const id of ['pActivity','pDate','pExecutor','pLocation','pType','pDepartment'])$(id)?.parentElement?.toggleAttribute('hidden',rec);
 for(const id of ['pAreas','pProjects','pCommittees'])$(id)?.closest('.report-section')?.toggleAttribute('hidden',rec);
 if(rec){$('trainingDocumentationFields').hidden=true;}
 const box=$('extensionPreview');box.replaceChildren();for(const [k,v]of extraSections(d)){if(!v?.length)continue;box.append(element('h4',k),element('p',Array.isArray(v)?v.join(' • '):v));}
 if(rec&&!allowed)box.append(element('p','تعذر التحقق من صلاحية إنشاء التكريم. أعيدي تحميل الصفحة.'));
 wasRecognition=rec;
}
export function restoreExtensions(d){
 if(!d.executionScope&&d.workshopType)$('executionScope').value=d.workshopType;
 if(!d.organizingEntity&&d.executingAgency)$('organizingEntity').value=d.executingAgency;
 $('recipientDetails').replaceChildren();
 if(d.recognition){const r=d.recognition;
 for(const [field,key]of Object.entries({recognitionTitle:'title',recognitionDate:'date',recognitionKind:'kind',recognitionKindOther:'kindOther',recognitionReason:'reason',recognitionPresenter:'presenter',recognitionNotes:'notes',recognitionAwardOther:'awardOther',recognitionHours:'hours'}))if(r[key]!=null)$(field).value=r[key];
 $('recognitionStaff').querySelectorAll('input').forEach(i=>i.checked=(r.recipientIds||r.recipients?.map(p=>p.id)||[]).includes(i.value));
 $('recognitionAwards').querySelectorAll('input').forEach(i=>{i.checked=r.awards?.includes(i.value)||false;if(i.checked)i.parentElement.hidden=false;});
 recipientEditors(r);
 }
}
