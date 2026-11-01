export const VALUES_PROJECT='مشروع أثر قيم التعلم في البيئة المدرسية';
export const VALUES_ALIASES=['مشروع أثر التعليم في البيئة المدرسية','أثر التعليم في البيئة المدرسية','مشروع اثر تعليم في البيئة المدرسية'];
export const canonicalProject=name=>VALUES_ALIASES.includes(name)?VALUES_PROJECT:name;
export const isValuesType=d=>canonicalProject(d?.type)===VALUES_PROJECT;
export const isValuesReport=d=>isValuesType(d)&&d?.valuesProject?.schemaVersion===1;
export function valuesPhotoGroups(d,photos){const phases=d.valuesProject?.photoPhases||[];return ['before','after'].map(phase=>({phase,title:phase==='before'?'قبل':'بعد',photos:photos.filter((_,i)=>phases[i]===phase)}));}
export function validateValuesProject(d,count){if(!isValuesReport(d))return;if(!d.activity?.trim()||!d.reportPreparedBy?.trim())throw Error('أكملي عنوان التقرير وانتظري تحميل اسم معدّة التقرير.');const phases=d.valuesProject.photoPhases;if(!Array.isArray(phases)||phases.some(p=>!['before','after'].includes(p))||phases.length>10||count!==undefined&&phases.length!==count)throw Error('صنّفي الصور ضمن قبل أو بعد، بحد أقصى 10 صور للمجموعتين.');}
