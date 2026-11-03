import {currentAcademicYear,dialogueDay} from './post-dialogue-model.js?v=20261103-dialogue';
export {currentAcademicYear,dialogueDay};
export const SESSION='جلسة التطوير المهني';
export const isSession=d=>d?.type===SESSION;
export const SESSION_GOALS=Object.freeze([
'تخطيط الدرس لإدارة الموقف التعليمي بما يراعي السلاسة في الانتقال بين الكفايات والمعارف والمهارات.',
'تضمين الموقف التعليمي إرشادات وتوجيهات واضحة.',
'استثمار الوقت بما يحقق أهداف التعلم.',
'إثارة دافعية المتعلمين بأساليب تحفز تمكنهم من المشاركة في التعلم.',
'إدارة الموقف التعليمي بما يعزز انضباطهم ويسهم في زيادة حماسهم نحو التعلم ويزيد إنتاجيتهم ونموهم وبناء شخصياتهم.',
'توظيف استراتيجيات تعليم وتعلم فعالة محورها المتعلم.',
'توظيف التكنولوجيا التفاعلية والأدوات الرقمية والموارد والمصادر التعليمية.',
'تنمية مهارات التفكير العليا للمتعلمين وتحدي قدراتهم.',
'توظيف التمايز لتلبية الاحتياجات التعليمية المختلفة للمتعلمين.',
'توظيف التقويم والاستفادة من نتائجه في دعم جميع فئات المتعلمين وفق احتياجاتهم.',
'متابعة أنشطة التعلم خلال الموقف التعليمي وتقديم تغذية راجعة شاملة للمتعلمين.',
'أخرى'
]);
export function sessionTitle(d){return 'استمارة جلسة التطوير المهني\nللفصل الدراسي ('+(d.semester==='الفصل الدراسي الثاني'?'الثاني':'الأول')+') للعام الدراسي \u2066'+(d.academicYear||currentAcademicYear()).replace('-','–')+'\u2069م';}
export function validateSession(d){if(!isSession(d))return;const p=d.professionalSession;if(p?.schemaVersion!==1||!p.teacher?.id||!p.leader?.id||!d.date)throw Error('اختاري المعلمة وقائد الجلسة والتاريخ.');if(!/^20\d{2}-20\d{2}$/.test(d.academicYear)||!['الفصل الدراسي الأول','الفصل الدراسي الثاني'].includes(d.semester))throw Error('راجعي الفصل والعام الدراسي بصيغة 2026-2027.');if(!Number.isInteger(Number(p.number))||Number(p.number)<1||Number(p.number)>10000)throw Error('رقم الجلسة يجب أن يكون عددًا صحيحًا بين 1 و10000.');if(!Array.isArray(p.goals)||p.goals.some(n=>!Number.isInteger(n)||n<1||n>12)||new Set(p.goals).size!==p.goals.length)throw Error('راجعي أهداف الجلسة المختارة.');if(p.goals.includes(12)&&!p.otherGoal?.trim())throw Error('اكتبي الهدف الآخر.');}
export function sessionRecords(rows,f={}){const seen=new Set();return rows.filter(r=>{const id=String(r.id),p=r.details?.professionalSession||{};if(seen.has(id)||r.deleted_at||r.status==='draft'||(r.activity_type||r.details?.type)!==SESSION)return false;seen.add(id);return (!f.teacher||p.teacher?.id===f.teacher)&&(!f.department||r.department===f.department)&&(!f.semester||r.semester===f.semester)&&(!f.from||r.activity_date>=f.from)&&(!f.to||r.activity_date<=f.to)&&(!f.query||[r.activity,r.department,p.teacher?.name,p.leader?.name,p.number].join(' ').includes(f.query));});}
export const sessionOverflow=()=>Error('محتوى الجلسة أطول من المساحة المتاحة في صفحة A4 واحدة. اختصري النصوص قبل الطباعة أو تنزيل PDF؛ لم يُحذف أي نص ولم يُصغّر الخط.');
