export const TEACHING_AREA = 'التعليم والتعلم والتقويم';
export const TEACHING_CONTENTS_LABEL = 'محتويات ملف التعليم والتعلم والتقويم';

export const TEACHING_CONTENTS = Object.freeze([
    'الفهرس',
    'الرؤية والرسالة',
    'استراتيجيات التعليم والتعلم',
    'الإدارة الصفية والوقتية',
    'أساليب التحفيز والتعزيز',
    'التقويم ودعم التعلم',
    'مهارات التفكير العليا وتحدي القدرات والابتكار والإبداع',
    'توظيف التكنولوجيا والمصادر'
].map((name, index) => Object.freeze({ id: String(index + 1), label: (index + 1) + '. ' + name })));

export function teachingContentIds(data) {
    if (!Array.isArray(data.areas) || !data.areas.includes(TEACHING_AREA) || !Array.isArray(data.teachingContents)) return [];
    return TEACHING_CONTENTS.filter(item => data.teachingContents.includes(item.id)).map(item => item.id);
}

export function teachingContentLabels(data) {
    const ids = teachingContentIds(data);
    return TEACHING_CONTENTS.filter(item => ids.includes(item.id)).map(item => item.label);
}
