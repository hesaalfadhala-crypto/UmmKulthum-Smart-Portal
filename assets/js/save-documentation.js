// Immutable submission + request_id make retries safe after a lost response.
export const PHOTO_BUCKET = 'school-documentation-images';

export async function checkSaveSchema(client) {
    const { error } = await client.from('documentations')
        .select('id,details,photo_files,request_id').limit(0);
    if (error) throw new Error('حفظ الصور غير مفعّل بعد في قاعدة البوابة. لم يتم إرسال التوثيق؛ بياناتك باقية في النموذج.');
}

export async function findSubmission(client, userId, requestId) {
    const { data, error } = await client.from('documentations').select('id')
        .eq('created_by', userId).eq('request_id', requestId).maybeSingle();
    if (error) throw new Error('تعذر التحقق من الحفظ. أعيدي المحاولة بنفس التوثيق عند عودة الاتصال.');
    return data;
}

export function databaseRecord(userId, submission) {
    const d = submission.data;
    return {
        created_by: userId, request_id: submission.requestId,
        activity: d.activity || null, activity_type: d.type || null,
        semester: d.semester || null, department: d.department || null,
        executor: d.executor || null, activity_date: d.date || null,
        location: d.location || null, goal: d.goal || null,
        implementation: d.implementation || null, results: d.impact || null,
        documentation_area: (d.areas || []).join(' • ') || null,
        projects: (d.projects || []).join(' • ') || null,
        committees: (d.committees || []).join(' • ') || null,
        target_categories: (d.targets || []).join(' • ') || null,
        competition_type: d.docCompetitionType || null,
        competition_organizer: d.docCompetitionOrganizer || null,
        competition_host: d.docCompetitionHost || null,
        competition_level: d.docCompetitionLevel || null,
        competition_students: d.docCompetitionStudents || null,
        competition_result: d.docCompetitionResult || null,
        competition_details: d.docCompetitionDetails || null,
        details: d, photo_files: submission.uploaded || []
    };
}

export async function preparePhoto(file) {
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type))
        throw new Error('اختاري صورًا بصيغة JPG أو PNG أو WebP.');
    if (file.size > 15 * 1024 * 1024)
        throw new Error('إحدى الصور أكبر من 15 ميجابايت. اختاري نسخة أصغر.');
    const url = URL.createObjectURL(file);
    try {
        const img = new Image();
        await new Promise((resolve, reject) => {
            img.onload = resolve;
            img.onerror = () => reject(new Error('تعذر قراءة إحدى الصور. أعيدي اختيارها.'));
            img.src = url;
        });
        const ratio = Math.min(1, 1800 / Math.max(img.naturalWidth, img.naturalHeight));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(img.naturalWidth * ratio));
        canvas.height = Math.max(1, Math.round(img.naturalHeight * ratio));
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#fff';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        let blob;
        for (const quality of [.86, .72, .55]) {
            blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', quality));
            if (blob && blob.size <= 3 * 1024 * 1024) break;
        }
        if (!blob || blob.size > 3 * 1024 * 1024)
            throw new Error('تعذر تجهيز إحدى الصور للحفظ. اختاري نسخة أصغر.');
        return { blob, width: canvas.width, height: canvas.height };
    } finally { URL.revokeObjectURL(url); }
}

export async function saveSubmission(client, userId, submission, checkpoint, progress = () => {}) {
    if (!submission.data.activity?.trim()) throw new Error('اكتبي اسم الفعالية أو النشاط.');
    if (submission.files.length > 10) throw new Error('يمكن إرفاق 10 صور كحد أقصى.');
    await checkSaveSchema(client);
    const existing = await findSubmission(client, userId, submission.requestId);
    if (existing) return existing;
    submission.uploaded ||= [];
    for (let i = submission.uploaded.length; i < submission.files.length; i++) {
        progress('جار حفظ الصورة ' + (i + 1) + ' من ' + submission.files.length + '…');
        const file = submission.files[i];
        const photo = await preparePhoto(file);
        const path = userId + '/' + submission.requestId + '/' + crypto.randomUUID() + '.jpg';
        const { error } = await client.storage.from(PHOTO_BUCKET).upload(path, photo.blob, {
            contentType: 'image/jpeg', upsert: false, cacheControl: '3600'
        });
        if (error) throw new Error('تعذر حفظ الصورة ' + (i + 1) + '. تحققي من الاتصال ثم أعيدي محاولة الحفظ.');
        submission.uploaded.push({ bucket: PHOTO_BUCKET, path,
            name: file.name, size: photo.blob.size, width: photo.width, height: photo.height });
        await checkpoint(submission);
    }
    progress('جار حفظ التوثيق في الأرشيف…');
    submission.sent = true;
    await checkpoint(submission);
    try {
        const { data, error } = await client.from('documentations')
            .insert(databaseRecord(userId, submission)).select('id').single();
        if (error || data?.id == null) throw new Error('تعذر تأكيد الحفظ.');
        return data;
    } catch {
        // An insert may have committed despite a network timeout. Never delete its photos.
        const recovered = await findSubmission(client, userId, submission.requestId);
        if (recovered) return recovered;
        throw new Error('لم يتأكد الحفظ في الأرشيف. بياناتك وصورك باقية في المسودة؛ أعيدي محاولة الحفظ بنفس التوثيق.');
    }
}
