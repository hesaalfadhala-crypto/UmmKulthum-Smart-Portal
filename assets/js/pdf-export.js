// Rasterized canvas preserves Arabic shaping and embeds every image. No external services.
async function loadImage(url) { const res = await fetch(url, { cache: 'no-store' }); if (!res.ok)
    throw new Error('تعذر تحميل إحدى صور التقرير؛ أعيدي المحاولة.'); const blob = await res.blob(); const src = URL.createObjectURL(blob); try {
    const img = new Image();
    await new Promise((resolve, reject) => { img.onload = () => resolve(); img.onerror = () => reject(new Error('الصورة غير صالحة')); img.src = src; });
    return img;
}
finally {
    URL.revokeObjectURL(src);
} }
export function packPDF(pages, width = 1240, height = 1754) {
    const encoder = new TextEncoder();
    const parts = [];
    const offsets = [0];
    let length = 0;
    const add = (s) => { const b = typeof s === 'string' ? encoder.encode(s) : s; parts.push(b); length += b.length; };
    const obj = (n, body) => { offsets[n] = length; add(n + ' 0 obj\n'); add(body); add('\nendobj\n'); };
    add('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
    obj(2, '<< /Type /Pages /Count ' + pages.length + ' /Kids [' + pages.map((_, i) => (3 + i * 3) + ' 0 R').join(' ') + '] >>');
    pages.forEach((jpeg, i) => { const n = 3 + i * 3; obj(n, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /XObject << /Im ' + (n + 1) + ' 0 R >> >> /Contents ' + (n + 2) + ' 0 R >>'); offsets[n + 1] = length; add((n + 1) + ' 0 obj\n<< /Type /XObject /Subtype /Image /Width ' + width + ' /Height ' + height + ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' + jpeg.length + ' >>\nstream\n'); add(jpeg); add('\nendstream\nendobj\n'); const content = 'q\n595.28 0 0 841.89 0 0 cm\n/Im Do\nQ'; obj(n + 2, '<< /Length ' + encoder.encode(content).length + ' >>\nstream\n' + content + '\nendstream'); });
    const xref = length;
    const count = 3 + pages.length * 3;
    add('xref\n0 ' + count + '\n0000000000 65535 f \n');
    for (let i = 1; i < count; i++)
        add(String(offsets[i]).padStart(10, '0') + ' 00000 n \n');
    add('trailer\n<< /Size ' + count + ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF');
    const output = new Uint8Array(length);
    let at = 0;
    for (const p of parts) {
        output.set(p, at);
        at += p.length;
    }
    return output;
}
export async function renderPDF(record) {
    await document.fonts.ready;
    const d = record.data;
    const logo = await loadImage('school-logo.png');
    const images = [];
    for (const p of record.photos)
        images.push(await loadImage(p.url));
    const W = 1240, H = 1754, M = 74, limit = 1560;
    const canvases = [];
    let c, ctx, y = 0;
    const start = () => { c = document.createElement('canvas'); c.width = W; c.height = H; ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H); ctx.direction = 'rtl'; ctx.textAlign = 'right'; ctx.fillStyle = '#174f4b'; ctx.font = 'bold 26px Tahoma, Arial'; ctx.fillText('بوابة أم كلثوم الذكية', W - M, 60); ctx.fillStyle = '#60736f'; ctx.font = '20px Tahoma, Arial'; ctx.direction = 'ltr'; ctx.textAlign = 'left'; ctx.fillText('2026–2027', M, 60); ctx.direction = 'rtl'; ctx.textAlign = 'right'; canvases.push(c); y = 100; };
    const ensure = (n) => { if (y + n > limit)
        start(); };
    const wrap = (value, maxWidth) => { const lines = []; for (const paragraph of value.split('\n')) {
        let line = '';
        for (const originalWord of paragraph.split(/\s+/)) {
            const words = [];
            let chunk = '';
            for (const letter of originalWord) {
                if (ctx.measureText(chunk + letter).width > maxWidth && chunk) {
                    words.push(chunk);
                    chunk = letter;
                } else chunk += letter;
            }
            words.push(chunk);
            for (const word of words) {
            const candidate = line ? line + ' ' + word : word;
            if (ctx.measureText(candidate).width > maxWidth && line) {
                lines.push(line);
                line = word;
            }
            else
                line = candidate;
            }
        }
        lines.push(line);
    } return lines; };
    const section = (label, value) => { if (!value?.length)
        return; const s = Array.isArray(value) ? value.join(' • ') : String(value); ctx.font = '24px Tahoma, Arial'; const lines = wrap(s, W - 2 * M - 285); ctx.font = 'bold 24px Tahoma, Arial'; const labels = wrap(label, 255); ensure(Math.max(80, labels.length * 35)); const count = Math.max(lines.length, labels.length); for (let i = 0; i < count; i++) {
        ensure(36);
        ctx.fillStyle = '#174f4b';
        ctx.font = 'bold 24px Tahoma, Arial';
        if (labels[i])
            ctx.fillText(labels[i], W - M, y + 25);
        ctx.fillStyle = '#263d39';
        ctx.font = '24px Tahoma, Arial';
        if (lines[i])
            ctx.fillText(lines[i], W - M - 285, y + 25);
        y += 35;
    } y += 18; };
    start();
    const logoH = (W - 2 * M) * logo.height / logo.width;
    ctx.drawImage(logo, M, y, W - 2 * M, logoH);
    y += logoH + 36;
    ctx.font = '22px Tahoma, Arial';
    ctx.fillStyle = '#60736f';
    ctx.fillText(d.semester, W - M, y);
    y += 52;
    ctx.fillStyle = '#174f4b';
    ctx.font = 'bold 37px Tahoma, Arial';
    for (const line of wrap(d.activity, W - 2 * M)) {
        ensure(50);
        ctx.font = 'bold 37px Tahoma, Arial';
        ctx.fillStyle = '#174f4b';
        ctx.fillText(line, W - M, y);
        y += 48;
    }
    ctx.fillStyle = '#b59646';
    ctx.fillRect(M, y, W - 2 * M, 3);
    y += 38;
    const meta = [['نوع الفعالية', d.type], ['القسم', d.department], ['المنفذة', d.executor], ['التاريخ', d.date], ['مكان التنفيذ', d.location]];
    for (const [k, v] of meta)
        if (v) {
            ctx.font = '24px Tahoma, Arial';
            const ls = wrap(k + ': ' + v, W - 2 * M);
            for (const l of ls) {
                ensure(35);
                ctx.font = '24px Tahoma, Arial';
                ctx.fillStyle = '#263d39';
                ctx.fillText(l, W - M, y);
                y += 35;
            }
        }
    y += 16;
    for (const [k, v] of [['المجالات المرتبطة', d.areas], ['المشاريع والمبادرات', d.projects], ['اللجان المرتبطة', d.committees], ['الفئات المستهدفة', d.targets], ['تفاصيل الفئة المستهدفة', d.target]])
        section(k, v);
    if (d.type === 'مسابقة وإنجاز طلابي')
        for (const [k, v] of [['اسم المسابقة', d.docCompetitionName], ['نوع المسابقة', d.docCompetitionType], ['الجهة المنظمة', d.docCompetitionOrganizer], ['الجهة المستضيفة', d.docCompetitionHost], ['المستوى', d.docCompetitionLevel], ['الطالبات المشاركات', d.docCompetitionStudents], ['النتيجة / المركز', d.docCompetitionResult], ['تفاصيل الإنجاز', d.docCompetitionDetails]])
            section(k, v);
    if (d.type === 'حصة احتياط')
        for (const [k, v] of [['الصف / الشعبة', d.reserveClass], ['رقم الحصة', d.reservePeriod], ['المعلمة الغائبة', d.originalTeacher], ['ما تم تنفيذه', d.reserveImplementation]])
            section(k, v);
    for (const [k, v] of [['الهدف', d.goal], ['وصف التنفيذ', d.implementation], ['النتائج والأثر', d.impact], ['التوصيات', d.recommendations]])
        section(k, v);
    if (images.length) {
        ensure(470);
        ctx.fillStyle = '#174f4b';
        ctx.font = 'bold 28px Tahoma, Arial';
        ctx.fillText('صور التوثيق', W - M, y + 26);
        y += 50;
        for (let i = 0; i < images.length; i += 2) {
            ensure(400);
            for (let j = 0; j < 2 && i + j < images.length; j++) {
                const img = images[i + j];
                const boxW = (W - 2 * M - 24) / 2, boxH = 340, x = W - M - boxW - j * (boxW + 24);
                const scale = Math.min(boxW / img.width, boxH / img.height);
                ctx.fillStyle = '#f3f6f5';
                ctx.fillRect(x, y, boxW, boxH);
                ctx.drawImage(img, x + (boxW - img.width * scale) / 2, y + (boxH - img.height * scale) / 2, img.width * scale, img.height * scale);
                ctx.font = '20px Tahoma, Arial';
                ctx.fillStyle = '#60736f';
                ctx.fillText('الصورة ' + (i + j + 1), x + boxW, y + 372);
            }
            y += 400;
        }
    }
    ctx.font = '22px Tahoma, Arial';
    const assistantLines = wrap(d.assistants.join(' • ') || '—', (W - 2 * M) / 2 - 20);
    ensure(70 + assistantLines.length * 31);
    y += 22;
    ctx.fillStyle = '#174f4b';
    ctx.font = 'bold 24px Tahoma, Arial';
    ctx.fillText('إشراف المديرة المساعدة', W - M, y);
    ctx.textAlign = 'left';
    ctx.fillText('مديرة المدرسة', M, y);
    ctx.textAlign = 'right';
    y += 36;
    ctx.font = '22px Tahoma, Arial';
    for (const l of assistantLines) {
        ctx.fillText(l, W - M, y);
        y += 31;
    }
    ctx.textAlign = 'left';
    ctx.fillText('أ. هيا محمد النعيمي', M, y - 31);
    ctx.textAlign = 'right';
    canvases.forEach((canvas, i) => { const g = canvas.getContext('2d'); g.strokeStyle = '#dce5e3'; g.beginPath(); g.moveTo(M, 1640); g.lineTo(W - M, 1640); g.stroke(); g.fillStyle = '#60736f'; g.font = '19px Tahoma, Arial'; g.direction = 'rtl'; g.textAlign = 'right'; g.fillText('رقم التوثيق: ' + String(record.id).slice(0, 8), W - M, 1675); g.textAlign = 'left'; g.fillText('صفحة ' + (i + 1) + ' من ' + canvases.length, M, 1675); });
    const pages = canvases.map(c => Uint8Array.from(atob(c.toDataURL('image/jpeg', .94).split(',')[1]), x => x.charCodeAt(0)));
    return packPDF(pages);
}
export async function exportPDF(record) { const bytes = await renderPDF(record); const blob = new Blob([bytes], { type: 'application/pdf' }); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = 'تقرير-' + record.data.activity.replace(/[\\/:*?"<>|]/g, '').slice(0, 70) + '-' + String(record.id).slice(0, 8) + '.pdf'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 20000); }
