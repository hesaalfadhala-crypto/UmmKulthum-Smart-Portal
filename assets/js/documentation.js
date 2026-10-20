import {appendReportText} from './report-text.js?v=20261021-spacing';
import {suggestDepartment} from './staff-display.js?v=20261019-staff';
import {agendaEvent} from './agenda-data.js';
import {renderSignatures,selectedSupervisors} from './report-signatures.js?v=20261021-spacing';
import {editContext,editableData,saveReportEdit} from './edit-documentation.js?v=20261021-recognition';
import {installOtherChoices,displayChoices,validateOtherChoices} from './documentation-choices.js?v=20261021-recognition';
import {installExtensions,loadExtensionAccess,collectExtensions,updateExtensions,restoreExtensions} from './documentation-extensions.js?v=20261021-spacing';
import {isRecognition,validateNewDetails} from './recognition-model.js?v=20261021-recognition';
import { client, requireUser, element, fetchRecord, normalize, loadPhotos } from './portal-data.js?v=20261017-edit-complete';
import { checkSaveSchema, saveSubmission } from './save-documentation.js?v=20261021-recognition';
import { readDraft, writeDraft, removeDraft } from './draft-store.js';

installExtensions();
const form = document.querySelector('.form');
const otherChoices=installOtherChoices(form);
const fields = [...form.querySelectorAll('input:not([type=file]),select,textarea')];
const images = document.getElementById('images');
const saveButton = document.getElementById('save');
const clearButton = document.getElementById('clear');
const editButton = document.getElementById('editDraft');
const status = document.getElementById('saveStatus');
const groups = { areas: 'areas', projects: 'project', committees: 'committee', targets: 'target', reportSupervisors:'supervisor' };
const editId=new URLSearchParams(location.search).get('edit');
if(editId){saveButton.classList.add('save-edits');document.body.classList.add('editing-report');}
let originalReport=null, retainedPhotos=[], retainedAttachments=[], existingPhotos=[], draftKey;
let profile, user, attachments = [], files = [], pending = null, saving = false, ready = false, previewUrls = [], attachmentPreviewUrls=[];
let requestId = crypto.randomUUID(), writeQueue = Promise.resolve();
let centerPrograms=[];let agendaSource=null;const agendaId=new URLSearchParams(location.search).get('agenda_event');

function message(text, error = false) {
    status.textContent = text;
    status.classList.toggle('error', error);status.classList.toggle('success',!error&&text==='تم حفظ التعديلات بنجاح');
}
function freeze() {
    fields.forEach(el => { el.disabled = !ready || saving || !!pending; });
    document.querySelectorAll('#recognitionStaff input,#recipientDetails input,#recipientDetails textarea').forEach(el=>el.disabled=!ready||saving||!!pending);
    images.disabled = !ready || saving || !!pending;document.getElementById('attachments').disabled=images.disabled;
    saveButton.disabled = !ready || saving;
    clearButton.disabled = !ready || saving || !!pending?.sent;
    document.querySelectorAll('#retainedFiles button').forEach(b=>b.disabled=!ready||saving||!!pending);
    editButton.hidden = !pending || !!pending.sent || saving;
    saveButton.textContent = saving ? 'جار الحفظ…' : pending ? 'إعادة محاولة الحفظ' : editId ? 'حفظ التعديلات' : 'حفظ في الأرشيف وعرض التقرير';
}
function collect() {
    const data = editId?{...originalReport?.details,academicYear:originalReport?.academic_year}:{};data.assistants ||= [];
    fields.filter(el => el.id && el.type !== 'checkbox').forEach(el => { data[el.id] = el.value.trim(); });
    for (const [key, cls] of Object.entries(groups))
        data[key] = [...form.querySelectorAll('.' + cls + '-checks input:checked')].map(el => el.value);
    const result=otherChoices.collect(collectExtensions(data));if(agendaSource)result.agendaEventId=agendaSource.id;return result;
}
function output(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    const text = Array.isArray(value) ? value.join(' • ') : value;
    appendReportText(el,text||'—');
    el.classList.toggle('empty', !text);
}
function preview() {
    const raw = collect(),d=displayChoices(raw);document.getElementById('motivationFields').hidden=!raw.projects.includes('تحفيز المعلمات');otherChoices.update();renderSignatures(document.getElementById('previewSignatures'),d);
    for (const [key, id] of Object.entries({ activity: 'pActivity', semester: 'pSemester', type: 'pType',
        department: 'pDepartment', executor: 'pExecutor', date: 'pDate', location: 'pLocation',
        goal: 'pGoal', implementation: 'pImplementation', impact: 'pImpact', recommendations: 'pRecommendations',
        areas: 'pAreas', projects: 'pProjects', committees: 'pCommittees', assistants: 'pAssistants',
        docCompetitionName: 'pCompetitionName', docCompetitionType: 'pCompetitionType',
        docCompetitionOrganizer: 'pCompetitionOrganizer', docCompetitionHost: 'pCompetitionHost',
        docCompetitionLevel: 'pCompetitionLevel', docCompetitionStudents: 'pCompetitionStudents',
        docCompetitionResult: 'pCompetitionResult', docCompetitionDetails: 'pCompetitionDetails',
        reserveClass: 'pReserveClass', reservePeriod: 'pReservePeriod', originalTeacher: 'pOriginalTeacher',
        reserveImplementation: 'pReserveImplementation' })) output(id, d[key]);
    output('pTarget', [...d.targets, d.target].filter(Boolean).join(' • '));
    const competition = !isRecognition(d)&&d.type === 'مسابقة وإنجاز طلابي', reserve = !isRecognition(d)&&d.type === 'حصة احتياط';
    document.getElementById('trainingDocumentationFields').hidden=d.type!=='ورشة تدريبية';updateExtensions(raw);
    document.getElementById('competitionDocumentationFields').style.display = competition ? 'block' : 'none';
    document.getElementById('competitionReport').style.display = competition ? 'block' : 'none';
    document.getElementById('reserveClassFields').style.display = reserve ? 'block' : 'none';
    document.getElementById('reserveClassReport').style.display = reserve ? 'block' : 'none';
    document.getElementById('assistantsReport').style.display = 'none';
    document.querySelector('.report-title').textContent = isRecognition(d)?d.recognition?.title||d.activity:'معاينة تقرير ' + d.type;
}
function previewPhotos() {
    previewUrls.forEach(url => URL.revokeObjectURL(url));
    previewUrls = [];
    const box = document.getElementById('reportImages');
    box.replaceChildren();
    document.getElementById('photosReport').style.display = files.length+retainedPhotos.length ? 'block' : 'none';
    for(const [i,p] of retainedPhotos.entries()){const photo=existingPhotos.find(x=>x.path===p.path);if(!photo)continue;const figure=element('figure'),img=element('img');img.src=photo.url;img.alt='صورة محفوظة '+(i+1);figure.append(img,element('figcaption','الصورة المحفوظة '+(i+1)));box.append(figure);}
    files.forEach((file, i) => {
        const figure = element('figure'), img = element('img');
        const url = URL.createObjectURL(file);
        previewUrls.push(url);
        img.src = url;
        img.alt = 'صورة التوثيق ' + (i + 1);
        figure.append(img, element('figcaption', 'الصورة ' + (i + 1)));
        box.append(figure);
    });
    document.getElementById('imageCount').textContent = (retainedPhotos.length+files.length) ? (retainedPhotos.length+files.length) + ' صور مرفقة' : 'لم تُرفق صور بعد';
    previewExisting();
}
function restore(data) {
    data={...data,executingEntity:data.executingEntity??data.executingAgency??'',reportSupervisors:selectedSupervisors(data)};
    if(editId){for(const el of fields.filter(el=>el.tagName==='SELECT'))if(data[el.id]&&!Array.from(el.options).some(o=>o.value===String(data[el.id]))){const o=element('option',String(data[el.id]));o.value=String(data[el.id]);el.append(o);}
    for(const [key,cls]of Object.entries(groups))for(const value of data[key]||[])if(!Array.from(form.querySelectorAll('.'+cls+'-checks input')).some(i=>i.value===value)){const label=element('label'),input=element('input');input.type='checkbox';input.value=value;label.append(input,document.createTextNode(value));form.querySelector('.'+cls+'-checks')?.append(label);}}
    fields.filter(el => el.id && el.type !== 'checkbox').forEach(el => {
        if (data[el.id] !== undefined) el.value = data[el.id];
    });
    for (const [key, cls] of Object.entries(groups))
        form.querySelectorAll('.' + cls + '-checks input').forEach(el => { el.checked = data[key]?.includes(el.value) || false; });
    restoreExtensions(data);otherChoices.restore(data);preview();
}
function persist(snapshot) {
    const copy = structuredClone(snapshot);
    const job = writeQueue.catch(() => {}).then(() => writeDraft(draftKey, copy));
    writeQueue = job;
    return job;
}
function draft() { return { requestId, data: collect(), files, attachments, pending, retainedPhotos, retainedAttachments, version:originalReport?.edit_version }; }
async function autosave() {
    if (!ready || saving || pending) return;
    try {
        await persist(draft());
        message(editId?'مسودة التعديلات محفوظة على هذا الجهاز. اضغطي «حفظ التعديلات» لتحديث التقرير الأصلي.':'المسودة محفوظة على هذا الجهاز. اضغطي «حفظ في الأرشيف» لإتمام التوثيق.');
    } catch (e) { message(e.message + ' أبقي الصفحة مفتوحة حتى تحفظي في الأرشيف.', true); }
}
form.addEventListener('input', () => { preview(); void autosave(); });
form.addEventListener('change', () => { preview(); void autosave(); });
images.addEventListener('change', () => {
    const selected = [...images.files];
    if (selected.length+(editId?retainedPhotos.length+files.length:0) > 10 || selected.some(file => !['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 15 * 1024 * 1024)) {
        message('اختاري حتى 10 صور JPG أو PNG أو WebP، بحجم لا يتجاوز 15 ميجابايت للصورة. الصور السابقة باقية.', true);
        images.value = '';
        return;
    }
    files = editId?[...files,...selected]:selected;
    if(editId)images.value='';
    previewPhotos();
    void autosave();
});
saveButton.addEventListener('click', async () => {
    if (!ready || saving) return;
    const details=collect();try{validateOtherChoices(details);validateNewDetails(details);}catch(e){message(e.message,true);return;}if(details.type==='ورشة تدريبية'&&details.trainingBeneficiaries!==''&&(!Number.isInteger(Number(details.trainingBeneficiaries))||Number(details.trainingBeneficiaries)<0||Number(details.trainingBeneficiaries)>10000)){message('عدد المستفيدات غير صالح.',true);return;}
    if (!collect().activity) {
        message('اكتبي اسم الفعالية أو النشاط.', true);
        document.getElementById('activity').focus();
        return;
    }
    saving = true;
    freeze();
    try {
        const currentUser = await requireUser();
        if (currentUser.id !== user.id) throw new Error('تغيّر حساب الدخول. أعيدي تحميل الصفحة قبل الحفظ.');
        if(agendaSource){const latest=await agendaEvent(agendaSource.id);if(latest.report_id){location.assign('report.html?id='+encodeURIComponent(latest.report_id));return;}}
        await checkSaveSchema(client);
        pending ||= { requestId, data: collect(), files, attachments, uploaded: [], uploadedAttachments:[], sent: false, ...(editId?{id:originalReport.id,version:originalReport.edit_version,retainedPhotos,retainedAttachments}:{} ) };
        await persist(draft());
        const row = await (editId?saveReportEdit:saveSubmission)(client, user.id, pending, () => persist(draft()), message);
        message(editId?'تم حفظ التعديلات بنجاح':'تم تأكيد الحفظ في الأرشيف. جار فتح التقرير النهائي…');
        // If local cleanup fails, request_id still recovers the saved server record on retry.
        try { await removeDraft(draftKey); } catch { /* server record is already confirmed */ }
        location.assign('report.html?id=' + encodeURIComponent(String(row.id))+(editId?'&saved_edit='+encodeURIComponent(pending.requestId):''));
    } catch (e) { if(agendaSource){try{const latest=await agendaEvent(agendaSource.id);if(latest.report_id){location.assign('report.html?id='+encodeURIComponent(latest.report_id));return;}}catch{}}message(e.message, true); }
    finally { saving = false; freeze(); }
});
editButton.addEventListener('click', async () => {
    if (!pending || pending.sent || saving) return;
    // No insert was sent yet. A new request keeps previously staged images separate.
    pending = null;
    requestId = crypto.randomUUID();
    freeze();
    await autosave();
});
clearButton.addEventListener('click', async () => {
    if (saving || pending?.sent || !confirm(editId?'إلغاء مسودة التعديل والعودة للتقرير دون تغيير النسخة المحفوظة؟':'مسح هذه المسودة وبدء توثيق جديد؟')) return;
    saving = true;
    freeze();
    try {
        await writeQueue.catch(() => {});
        await removeDraft(draftKey);
        if(editId){location.assign('report.html?id='+encodeURIComponent(editId));return;}
        fields.forEach(el => {
            if (el.type === 'checkbox') el.checked = false;
            else if (el.tagName === 'SELECT') el.selectedIndex = 0;
            else el.value = '';
        });
        document.querySelectorAll('#recognitionStaff input,#recipientDetails input,#recipientDetails textarea').forEach(i=>i.checked=false);
        files = [];attachments=[];document.getElementById('attachments').value=''; pending = null; requestId = crypto.randomUUID(); images.value = '';
        document.getElementById('reportPreparedBy').value=profile?.full_name||user.user_metadata?.full_name||'';
        suggestDepartment(document.getElementById('department'),profile);preview(); previewPhotos(); message('ابدئي توثيقًا جديدًا.');
    } catch (e) { message(e.message, true); }
    finally { saving = false; freeze(); }
});
window.addEventListener('beforeunload', event => {
    if (saving) { event.preventDefault(); event.returnValue = ''; }
});
document.getElementById('centerProgramId').addEventListener('change',()=>{const p=centerPrograms.find(p=>p.id===document.getElementById('centerProgramId').value);if(p){document.getElementById('executionScope').value=p.workshop_type||'';document.getElementById('organizingEntity').value=p.executing_agency||'';document.getElementById('hostingEntity').value=p.hosting_entity||'';preview();void autosave();}});
freeze();
try {
    user = await requireUser();
    const {data:loadedProfile,error:profileError}=await client.from('profiles').select('full_name,job_title,department,departments').eq('id',user.id).single();
    profile=loadedProfile;
    document.querySelector('.supervisor-checks input[value=assistant]').checked=true;
    if(profileError)throw new Error('تعذر تحميل اسم المستخدمة. أعيدي المحاولة.');
    document.getElementById('reportPreparedBy').value=profile?.full_name||user.user_metadata?.full_name||'';
    if(agendaId&&!editId){agendaSource=await agendaEvent(agendaId);if(agendaSource.report_id){location.replace('report.html?id='+encodeURIComponent(agendaSource.report_id));throw new Error('جار فتح التقرير الأصلي.');}}
    draftKey=editId?user.id+':report:'+editId:agendaSource?user.id+':agenda:'+agendaSource.id:user.id;
    await loadExtensionAccess();
    const {data:programs,error:programError}=await client.from('support_programs').select('id,title,starts_at,status,workshop_type,executing_agency,hosting_entity').order('starts_at',{ascending:false});
    if(!programError){centerPrograms=(programs||[]).filter(p=>p.status!=='cancelled');for(const p of centerPrograms){const option=element('option',p.title);option.value=p.id;document.getElementById('centerProgramId').append(option);}}
    if(editId){
        originalReport=await fetchRecord(editId);
        if(!(await editContext(client,editId)).can_edit)throw new Error('ليست لديكِ صلاحية تعديل هذا التقرير.');
        retainedPhotos=structuredClone(originalReport.photo_files||[]);retainedAttachments=structuredClone(originalReport.attachment_files||[]);
        existingPhotos=await loadPhotos(originalReport);
        const data=editableData(originalReport,normalize(originalReport));data.reportPreparedBy ||= data.executor||'';restore(data);
        document.querySelector('h1').textContent='تعديل التقرير';clearButton.textContent='إلغاء مسودة التعديل';
        message('تعديل التقرير رقم '+originalReport.id+'؛ الحفظ يحدّث النسخة الأصلية. إزالة صورة تفصلها عن التقرير ولا تحذف الملف المخزن.');
    }
    let saved;
    try { saved = await readDraft(draftKey); }
    catch (e) { message(e.message, true); }
    if(saved&&editId&&saved.version!==originalReport.edit_version&&!saved.pending?.sent)throw new Error('توجد مسودة لتعديل نسخة سابقة. افتحي التقرير الأحدث؛ المسودة محفوظة.');
    if (saved) {
        if(editId){retainedPhotos=saved.retainedPhotos||[];retainedAttachments=saved.retainedAttachments||[];}
        requestId = saved.requestId; files = saved.files || [];attachments=saved.attachments||[];document.getElementById('attachmentCount').textContent=attachments.length+' ملفات PDF مرفقة'; pending = saved.pending || null;
        restore(saved.data || {});
        message(pending ? 'استُعيدت محاولة الحفظ السابقة. أعيدي الحفظ للتحقق من الأرشيف دون إنشاء نسخة مكررة.' : 'استُعيدت المسودة وصورها من هذا الجهاز.');
    } else if(!editId){const params=new URLSearchParams(location.search),program=centerPrograms.find(p=>p.id===params.get('center_program'));if(program||params.get('type')==='workshop'){document.getElementById('type').value='ورشة تدريبية';if(program){document.getElementById('centerProgramId').value=program.id;document.getElementById('activity').value=program.title;document.getElementById('executionScope').value=program.workshop_type||'';document.getElementById('organizingEntity').value=program.executing_agency||'';document.getElementById('hostingEntity').value=program.hosting_entity||'';const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bahrain',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(program.starts_at));const d=Object.fromEntries(parts.map(p=>[p.type,p.value]));document.getElementById('date').value=d.year+'-'+d.month+'-'+d.day;}}preview();}
    if(!saved&&agendaSource){const e=agendaSource;for(const [id,value]of Object.entries({activity:e.title,date:e.event_date,executor:e.responsible_names.join(' • '),location:e.location,type:e.kind==='workshop'?'ورشة تدريبية':'فعالية',executionScope:'internal'}))document.getElementById(id).value=value;const dep=document.getElementById('department');if(![...dep.options].some(o=>o.value===e.department)){dep.add(new Option(e.department,e.department));}dep.value=e.department;preview();}
    if(!saved&&new URLSearchParams(location.search).get('project')==='recognition'){document.querySelector('#recognitionProjectOption input').checked=true;document.getElementById('type').value='فعالية';preview();}
    if(!saved&&!editId&&!agendaSource){suggestDepartment(document.getElementById('department'),profile);preview();}
    previewPhotos(); ready = true; freeze();
} catch (e) {
    message(e.message, true);
    const login = element('a', 'تسجيل الدخول');
    login.href = 'login.html';
    status.append(document.createTextNode(' '), login);
}

document.getElementById('attachments').addEventListener('change',()=>{const picked=[...document.getElementById('attachments').files];if(picked.length+(editId?retainedAttachments.length+attachments.length:0)>5||picked.some(f=>f.size>8388608||!f.name.toLowerCase().endsWith('.pdf'))){message('اختاري حتى 5 ملفات PDF، بحجم 8 ميغابايت لكل ملف.',true);document.getElementById('attachments').value='';return;}attachments=editId?[...attachments,...picked]:picked;if(editId)document.getElementById('attachments').value='';previewExisting();document.getElementById('attachmentCount').textContent=(attachments.length+retainedAttachments.length)+' ملفات PDF مرفقة';void autosave();});

function previewExisting(){
 attachmentPreviewUrls.forEach(u=>URL.revokeObjectURL(u));attachmentPreviewUrls=[];
 let box=document.getElementById('retainedFiles');if(!box){box=element('section');box.id='retainedFiles';images.parentElement.after(box);}box.replaceChildren();
 const item=(label,remove)=>{const b=element('button','إزالة '+label);b.type='button';b.disabled=saving||!!pending;b.addEventListener('click',()=>{remove();previewPhotos();void autosave();});return b;};
 retainedPhotos.forEach((p,i)=>{const f=element('figure'),photo=existingPhotos.find(x=>x.path===p.path);if(photo){const img=element('img');img.src=photo.url;img.alt='صورة محفوظة '+(i+1);img.style.maxWidth='160px';f.append(img);}f.append(item('الصورة المحفوظة '+(i+1),()=>retainedPhotos=retainedPhotos.filter(x=>x.path!==p.path)));box.append(f);});
 files.forEach((f,i)=>box.append(item('الصورة الجديدة '+(i+1),()=>files.splice(i,1))));
 retainedAttachments.forEach(f=>box.append(item('المرفق '+f.name,()=>retainedAttachments=retainedAttachments.filter(x=>x.path!==f.path))));
 attachments.forEach((f,i)=>{const row=element('div'),a=element('a','معاينة '+f.name);const url=URL.createObjectURL(f);attachmentPreviewUrls.push(url);a.href=url;a.target='_blank';a.rel='noopener';row.append(a,document.createTextNode(' '),item('المرفق الجديد '+f.name,()=>attachments.splice(i,1)));box.append(row);});
 document.getElementById('attachmentCount').textContent=(retainedAttachments.length+attachments.length)+' ملفات PDF مرفقة';
}
