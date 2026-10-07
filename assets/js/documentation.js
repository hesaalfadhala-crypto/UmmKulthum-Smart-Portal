import { client, requireUser, element } from './portal-data.js';
import { checkSaveSchema, saveSubmission } from './save-documentation.js';
import { readDraft, writeDraft, removeDraft } from './draft-store.js';

const form = document.querySelector('.form');
const fields = [...form.querySelectorAll('input:not([type=file]),select,textarea')];
const images = document.getElementById('images');
const saveButton = document.getElementById('save');
const clearButton = document.getElementById('clear');
const editButton = document.getElementById('editDraft');
const status = document.getElementById('saveStatus');
const groups = { areas: 'areas', projects: 'project', committees: 'committee', targets: 'target', assistants: 'assistant' };
let user, files = [], pending = null, saving = false, ready = false, previewUrls = [];
let requestId = crypto.randomUUID(), writeQueue = Promise.resolve();

function message(text, error = false) {
    status.textContent = text;
    status.classList.toggle('error', error);
}
function freeze() {
    fields.forEach(el => { el.disabled = !ready || saving || !!pending; });
    images.disabled = !ready || saving || !!pending;
    saveButton.disabled = !ready || saving;
    clearButton.disabled = !ready || saving || !!pending?.sent;
    editButton.hidden = !pending || !!pending.sent || saving;
    saveButton.textContent = saving ? 'جار الحفظ…' : pending ? 'إعادة محاولة الحفظ' : 'حفظ في الأرشيف وعرض التقرير';
}
function collect() {
    const data = {};
    fields.filter(el => el.id && el.type !== 'checkbox').forEach(el => { data[el.id] = el.value.trim(); });
    for (const [key, cls] of Object.entries(groups))
        data[key] = [...form.querySelectorAll('.' + cls + '-checks input:checked')].map(el => el.value);
    return data;
}
function output(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    const text = Array.isArray(value) ? value.join(' • ') : value;
    el.textContent = text || '—';
    el.classList.toggle('empty', !text);
}
function preview() {
    const d = collect();
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
    const competition = d.type === 'مسابقة وإنجاز طلابي', reserve = d.type === 'حصة احتياط';
    document.getElementById('competitionDocumentationFields').style.display = competition ? 'block' : 'none';
    document.getElementById('competitionReport').style.display = competition ? 'block' : 'none';
    document.getElementById('reserveClassFields').style.display = reserve ? 'block' : 'none';
    document.getElementById('reserveClassReport').style.display = reserve ? 'block' : 'none';
    document.getElementById('assistantsReport').style.display = d.assistants.length ? 'block' : 'none';
    document.querySelector('.report-title').textContent = 'معاينة تقرير ' + d.type;
}
function previewPhotos() {
    previewUrls.forEach(url => URL.revokeObjectURL(url));
    previewUrls = [];
    const box = document.getElementById('reportImages');
    box.replaceChildren();
    document.getElementById('photosReport').style.display = files.length ? 'block' : 'none';
    files.forEach((file, i) => {
        const figure = element('figure'), img = element('img');
        const url = URL.createObjectURL(file);
        previewUrls.push(url);
        img.src = url;
        img.alt = 'صورة التوثيق ' + (i + 1);
        figure.append(img, element('figcaption', 'الصورة ' + (i + 1)));
        box.append(figure);
    });
    document.getElementById('imageCount').textContent = files.length ? files.length + ' صور مرفقة' : 'لم تُرفق صور بعد';
}
function restore(data) {
    fields.filter(el => el.id && el.type !== 'checkbox').forEach(el => {
        if (data[el.id] !== undefined) el.value = data[el.id];
    });
    for (const [key, cls] of Object.entries(groups))
        form.querySelectorAll('.' + cls + '-checks input').forEach(el => { el.checked = data[key]?.includes(el.value) || false; });
    preview();
}
function persist(snapshot) {
    const copy = structuredClone(snapshot);
    const job = writeQueue.catch(() => {}).then(() => writeDraft(user.id, copy));
    writeQueue = job;
    return job;
}
function draft() { return { requestId, data: collect(), files, pending }; }
async function autosave() {
    if (!ready || saving || pending) return;
    try {
        await persist(draft());
        message('المسودة محفوظة على هذا الجهاز. اضغطي «حفظ في الأرشيف» لإتمام التوثيق.');
    } catch (e) { message(e.message + ' أبقي الصفحة مفتوحة حتى تحفظي في الأرشيف.', true); }
}
form.addEventListener('input', () => { preview(); void autosave(); });
form.addEventListener('change', () => { preview(); void autosave(); });
images.addEventListener('change', () => {
    const selected = [...images.files];
    if (selected.length > 10 || selected.some(file => !['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 15 * 1024 * 1024)) {
        message('اختاري حتى 10 صور JPG أو PNG أو WebP، بحجم لا يتجاوز 15 ميجابايت للصورة. الصور السابقة باقية.', true);
        images.value = '';
        return;
    }
    files = selected;
    previewPhotos();
    void autosave();
});
saveButton.addEventListener('click', async () => {
    if (!ready || saving) return;
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
        await checkSaveSchema(client);
        pending ||= { requestId, data: collect(), files, uploaded: [], sent: false };
        await persist(draft());
        const row = await saveSubmission(client, user.id, pending, () => persist(draft()), message);
        message('تم تأكيد الحفظ في الأرشيف. جار فتح التقرير النهائي…');
        // If local cleanup fails, request_id still recovers the saved server record on retry.
        try { await removeDraft(user.id); } catch { /* server record is already confirmed */ }
        location.assign('report.html?id=' + encodeURIComponent(String(row.id)));
    } catch (e) { message(e.message, true); }
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
    if (saving || pending?.sent || !confirm('مسح هذه المسودة وبدء توثيق جديد؟')) return;
    saving = true;
    freeze();
    try {
        await writeQueue.catch(() => {});
        await removeDraft(user.id);
        fields.forEach(el => {
            if (el.type === 'checkbox') el.checked = false;
            else if (el.tagName === 'SELECT') el.selectedIndex = 0;
            else el.value = '';
        });
        files = []; pending = null; requestId = crypto.randomUUID(); images.value = '';
        preview(); previewPhotos(); message('ابدئي توثيقًا جديدًا.');
    } catch (e) { message(e.message, true); }
    finally { saving = false; freeze(); }
});
window.addEventListener('beforeunload', event => {
    if (saving) { event.preventDefault(); event.returnValue = ''; }
});
freeze();
try {
    user = await requireUser();
    let saved;
    try { saved = await readDraft(user.id); }
    catch (e) { message(e.message, true); }
    if (saved) {
        requestId = saved.requestId; files = saved.files || []; pending = saved.pending || null;
        restore(saved.data || {});
        message(pending ? 'استُعيدت محاولة الحفظ السابقة. أعيدي الحفظ للتحقق من الأرشيف دون إنشاء نسخة مكررة.' : 'استُعيدت المسودة وصورها من هذا الجهاز.');
    } else preview();
    previewPhotos(); ready = true; freeze();
} catch (e) {
    message(e.message, true);
    const login = element('a', 'تسجيل الدخول');
    login.href = 'login.html';
    status.append(document.createTextNode(' '), login);
}
