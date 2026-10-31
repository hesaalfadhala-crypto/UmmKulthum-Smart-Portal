export const EXCHANGE_TYPE='زيارة صفية';
export const EXCHANGE_TITLE='استمارة الزيارات الصفية التبادلية';
export const isExchange=d=>['زيارة','زيارة صفية','زيارة صفية تبادلية'].includes(d?.type);
export const isExchangeReport=d=>isExchange(d)&&d?.exchangeVisit?.schemaVersion===1;
export const DOMAINS=[
 ['التخطيط وإدارة الموقف التعليمي',[
 'اتساق تخطيط الدرس مع الكفايات التعليمية للمنهج، ومراعاة احتياجات الطلبة.',
 'تضمين الموقف التعليمي إرشادات وتوجيهات واضحة لاستثمار الوقت بما يحقق أهداف التعلم بصورة منتجة.',
 'تحفيز الطلبة ورفع دافعيتهم بأساليب تمكنهم من المشاركة في التعلم وبناء شخصياتهم.']],
 ['التعليم والتعلم والتقويم',[
 'توظيف استراتيجيات تعليم وتعلم فعالة.',
 'توظيف التقويم والاستفادة من نتائجه في دعم جميع فئات الطلبة وفق احتياجاتهم.',
 'تنمية مهارات التفكير العليا للطلبة وتحدي قدراتهم.',
 'توظيف التعلم المتمايز لتلبية الاحتياجات المتنوعة للطلبة على اختلاف فئاتهم.']],
 ['الموارد التعليمية والتكنولوجية',[
 'توظيف المصادر والموارد التعليمية والتكنولوجية.',
 'تنمية مهارات الطلبة التكنولوجية ومهارات البحث والتعلم الذاتي، وتشجيعهم على إنتاج المحتوى التعليمي الرقمي.']],
 ['الإنجاز الأكاديمي',[
 'إظهار الطلبة المعارف والمهارات الأساسية وفقًا لمرحلتهم التعليمية.',
 'تحقيق الطلبة التقدم خلال الدروس، واكتساب مهارات التعلم.']],
 ['التطور الشخصي للطلبة',[
 'التزام الطلبة بالقيم الإسلامية والوطنية والرقمية، والاستعمال الآمن للتكنولوجيا.',
 'التزام الطلبة السلوك الإيجابي نحو التعلم، والانضباط الذاتي، وتحمل المسؤوليات المختلفة.',
 'قدرة الطلبة على التواصل والمشاركة الفاعلة خلال تعلمهم.',
 'إظهار الطلبة الثقة بالنفس، والقدرة على القيادة والمبادرة والابتكار.']]
];
export const CRITERIA=DOMAINS.flatMap(([domain,items],i)=>items.map((text,j)=>({id:`d${i+1}c${j+1}`,domain,text})));
export function visitDay(date){if(!/^\d{4}-\d{2}-\d{2}$/.test(date||''))return '';return new Intl.DateTimeFormat('ar-BH',{weekday:'long',timeZone:'Asia/Bahrain'}).format(new Date(date+'T12:00:00+03:00'));}
export function visitRows(d){const v=d.exchangeVisit||{};return [
 ['الفصل الدراسي',d.semester,'العام الدراسي',d.academicYear],
 ['عنوان الدرس',v.lessonTitle||d.activity,'المادة',v.subject],
 ['الصف',v.className,'المعلمة المزارة',v.visitedName],
 ['اليوم والتاريخ',[visitDay(d.date),d.date].filter(Boolean).join(' — '),'نوع الزيارة',v.kind],
 ['المعلمة الزائرة',v.visitorName||d.executor,'القسم',d.department]
 ];}
export function validateExchange(d){if(!isExchange(d)||!d.exchangeVisit)return;const v=d.exchangeVisit;
 if(!d.semester||!d.academicYear||!d.department||!d.date||!v.lessonTitle?.trim()||!v.subject?.trim()||!v.className?.trim()||!v.visitedId||!v.visitorId||!['داخل القسم','خارج القسم'].includes(v.kind))throw Error('أكملي بيانات الزيارة الصفية التبادلية.');
 if(!Array.isArray(v.selected)||v.selected.some(id=>!CRITERIA.some(c=>c.id===id))||new Set(v.selected).size!==v.selected.length)throw Error('راجعي الممارسات المختارة.');
 if(!v.practices?.trim())throw Error('اكتبي أبرز الممارسات المستفادة من الزيارة.');
}
