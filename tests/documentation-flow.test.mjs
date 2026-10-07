// Integration model; deliberately uses synthetic users and images, never school records.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { createCanvas, Image: NativeImage, GlobalFonts } = require('@napi-rs/canvas');
GlobalFonts.registerFromPath('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 'Tahoma');
const root = path.resolve(import.meta.dirname, '..');
const objects = new Map();
let objectId = 0, downloadedName;
URL.createObjectURL = blob => { const url = 'blob:test-' + objectId++; objects.set(url, blob); return url; };
URL.revokeObjectURL = url => objects.delete(url);
globalThis.Image = function BrowserImage() {
    const image = new NativeImage();
    const descriptor = Object.getOwnPropertyDescriptor(NativeImage.prototype, 'src');
    Object.defineProperty(image, 'src', { get() { return descriptor.get.call(image); }, set(value) {
        const blob = objects.get(value);
        if (blob) blob.arrayBuffer().then(buffer => descriptor.set.call(image, Buffer.from(buffer)));
        else descriptor.set.call(image, value);
    } });
    return image;
};
globalThis.document = {
    fonts: { ready: Promise.resolve() },
    createElement(tag) {
        if (tag === 'a') return { click() { downloadedName = this.download; } };
        assert.equal(tag, 'canvas');
        const canvas = createCanvas(1, 1);
        canvas.toBlob = async (callback, mime, quality) => callback(new Blob([await canvas.encode('jpeg', Math.round(quality * 100))], { type: mime }));
        return canvas;
    }
};

function model() {
    const rows = [], stored = new Map();
    const state = { rows, stored, uploads: 0, inserts: 0, failUpload: 0, missingSchema: false, loseResponse: false, signingError: false };
    class Query {
        constructor() { this.filters = []; this.selection = '*'; }
        select(s) { this.selection = s; return this; }
        eq(key, value) { this.filters.push([key, value]); return this; }
        order() { return this; }
        range(start, end) { this.slice = [start, end + 1]; return this; }
        limit(n) { this.slice = [0, n]; return this; }
        insert(value) { this.value = value; return this; }
        single() { this.one = true; return this.run(); }
        maybeSingle() { this.one = true; return this.run(); }
        then(resolve, reject) { return this.run().then(resolve, reject); }
        async run() {
            if (state.missingSchema && /details|request_id/.test(this.selection)) return { data: null, error: { code: '42703' } };
            let matches;
            if (this.value) {
                state.inserts++;
                if (rows.some(row => row.created_by === this.value.created_by && row.request_id === this.value.request_id))
                    return { data: null, error: { code: '23505' } };
                const row = { ...structuredClone(this.value), id: rows.length + 1, created_at: '2026-10-07T12:00:00Z' };
                rows.push(row); matches = [row];
                if (state.loseResponse) { state.loseResponse = false; throw new Error('network timeout after commit'); }
            } else matches = rows.filter(row => this.filters.every(([key, value]) => String(row[key]) === String(value)));
            if (this.slice) matches = matches.slice(...this.slice);
            return { data: this.one ? structuredClone(matches[0] || null) : structuredClone(matches), error: null };
        }
    }
    state.client = {
        auth: { getUser: async () => ({ data: { user: { id: 'synthetic-user' } }, error: null }) },
        from() { return new Query(); },
        storage: { from(bucket) { return {
            async upload(key, blob, options) {
                assert.equal(bucket, 'school-documentation-images');
                assert.equal(options.upsert, false);
                state.uploads++;
                if (state.uploads === state.failUpload) return { error: { message: 'disconnected' } };
                stored.set(key, blob); return { error: null };
            },
            async createSignedUrls(keys) {
                if (state.signingError) return { error: null, data: [] };
                return { error: null, data: keys.map(key => ({ signedUrl: 'https://synthetic.invalid/' + key })) };
            }
        }; } }
    };
    return state;
}
let active = model();
globalThis.window = { supabase: { createClient: () => active.client } };
const { saveSubmission } = await import('../assets/js/save-documentation.js');
const { normalize, loadPhotos, fetchRecords, fetchRecord } = await import('../assets/js/portal-data.js');
const { renderPDF, exportPDF } = await import('../assets/js/pdf-export.js');

function imageFile(width, height, color, name) {
    const canvas = createCanvas(width, height), ctx = canvas.getContext('2d');
    ctx.fillStyle = color; ctx.fillRect(0, 0, width, height);
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 15; ctx.strokeRect(10, 10, width - 20, height - 20);
    return new File([canvas.toBuffer('image/jpeg')], name, { type: 'image/jpeg' });
}
const files = [imageFile(2400, 1400, '#174f4b', 'landscape.jpg'), imageFile(900, 1500, '#b59646', 'portrait.jpg')];
function submission() { return { requestId: crypto.randomUUID(), files, uploaded: [], data: {
    activity: 'اختبار توثيق بصورتين', type: 'حصة احتياط', semester: 'الفصل الدراسي الأول',
    department: 'الرياضيات', executor: 'مستخدمة اختبار', date: '2026-10-07', location: 'قاعة اختبار',
    areas: ['التعليم والتعلم والتقويم'], projects: ['الخوارزمي'], committees: ['لجنة الموهبة'],
    targets: ['جميع الطالبات'], target: 'فئة اختبار', assistants: ['أ. حصه سند الفضاله'],
    reserveClass: '2 إعدادي / 3', reservePeriod: 'الثالثة', originalTeacher: 'معلمة اختبار',
    reserveImplementation: 'نشاط تدريبي تجريبي', goal: 'التحقق من دورة حفظ كاملة',
    implementation: 'حفظ صور أفقية ورأسية واسترجاعها', impact: 'تم التحقق', recommendations: 'نص اختبار'
} }; }

test('upload → archive → retrieve → static PDF preserves fields and all images', async () => {
    let savedDraft;
    const input = submission();
    const row = await saveSubmission(active.client, 'synthetic-user', input, async value => { savedDraft = structuredClone(value); });
    assert.equal(active.rows.length, 1);
    assert.equal(active.uploads, 2);
    assert.equal(savedDraft.sent, true);
    const archive = await fetchRecords();
    assert.equal(archive[0].id, row.id);
    const record = normalize(await fetchRecord(row.id));
    assert.equal(record.data.reserveImplementation, input.data.reserveImplementation);
    assert.deepEqual(record.data.projects, input.data.projects);
    record.photos = await loadPhotos(record);
    assert.equal(record.photos.length, 2);
    assert.equal(record.photos[0].width, 1800);
    assert.equal(record.photos[1].height, 1500);
    globalThis.fetch = async url => {
        if (url === 'school-logo.png') return new Response(await fs.readFile(path.join(root, 'school-logo.png')));
        if (objects.has(url)) return new Response(objects.get(url));
        const photo = active.stored.get(String(url).replace('https://synthetic.invalid/', ''));
        return photo ? new Response(photo) : new Response('', { status: 404 });
    };
    const pdf = await renderPDF(record);
    assert.equal(new TextDecoder().decode(pdf.slice(0, 8)), '%PDF-1.4');
    assert.ok(pdf.length > 50000);
    const destination = process.env.PORTAL_QA_OUTPUT;
    if (destination) { await fs.mkdir(destination, { recursive: true }); await fs.writeFile(path.join(destination, 'original-portal-flow.pdf'), pdf); }
    await exportPDF(record); // catches the original numeric-id filename regression
    assert.match(downloadedName, /-1\.pdf$/);
    const large = { ...record, data: { ...record.data, implementation: 'شرح طويل لتجربة التوثيق والاسترجاع.\n'.repeat(90) }, photos: Array.from({ length: 10 }, (_, i) => record.photos[i % 2]) };
    const longPDF = await renderPDF(large);
    assert.ok(/\/Count ([4-9]|[1-9][0-9]+)/.test(new TextDecoder().decode(longPDF)));
    if (destination) await fs.writeFile(path.join(destination, 'original-portal-long.pdf'), longPDF);
});

test('lost insert response and repeated save recover one record without re-upload', async () => {
    const m = model(); m.loseResponse = true;
    const input = submission();
    const first = await saveSubmission(m.client, 'synthetic-user', input, async () => {});
    const retry = await saveSubmission(m.client, 'synthetic-user', input, async () => {});
    assert.equal(first.id, retry.id); assert.equal(m.rows.length, 1);
    assert.equal(m.inserts, 1); assert.equal(m.uploads, 2); assert.equal(m.stored.size, 2);
});

test('partial image failure saves no incomplete record and resumes staged photos', async () => {
    const m = model(); m.failUpload = 2; const input = submission();
    await assert.rejects(saveSubmission(m.client, 'synthetic-user', input, async () => {}), /الصورة 2/);
    assert.equal(m.rows.length, 0); assert.equal(input.uploaded.length, 1);
    m.failUpload = 0;
    await saveSubmission(m.client, 'synthetic-user', input, async () => {});
    assert.equal(m.rows.length, 1); assert.equal(m.uploads, 3); assert.equal(m.stored.size, 2);
});

test('missing backend setup uploads nothing and inserts nothing', async () => {
    const m = model(); m.missingSchema = true;
    await assert.rejects(saveSubmission(m.client, 'synthetic-user', submission(), async () => {}), /غير مفعّل/);
    assert.equal(m.uploads, 0); assert.equal(m.inserts, 0);
});

test('image signing failure blocks a report instead of silently dropping its photos', async () => {
    active.signingError = true;
    await assert.rejects(loadPhotos(active.rows[0]), /تحميل صور/);
    active.signingError = false;
});

test('archive pagination retrieves more than the first page', async () => {
    for (let i = 2; i <= 405; i++) active.rows.push({ id: i, activity: 'اختبار ' + i });
    assert.equal((await fetchRecords()).length, 405);
    const old = normalize({ id: 12, activity: 'سجل قديم', results: 'أثر محفوظ', competition_result: 'المركز الأول' });
    assert.equal(old.data.impact, 'أثر محفوظ'); assert.equal(old.data.docCompetitionResult, 'المركز الأول');
    assert.deepEqual(old.photos, []);
});
