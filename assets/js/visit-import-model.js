export const MAX_PDF_BYTES=50*1024*1024;
export const normalizeName=s=>String(s||'').normalize('NFKC').replace(/[أإآ]/g,'ا').replace(/ى/g,'ي').replace(/ة/g,'ه').replace(/[\u064B-\u065Fـ\s.]/g,'');
export function matchPerson(name,people){const found=people.filter(p=>normalizeName(p.full_name)===normalizeName(name));return found.length===1?found[0].id:'';}
export function proposal(raw,offset,context){
 const teacher_id=matchPerson(raw.teacher_name,context.teachers),teacher=context.teachers.find(t=>t.id===teacher_id);
 return {key:crypto.randomUUID(),pages:[...new Set((raw.pages||[]).map(p=>p+offset))],teacher_name:raw.teacher_name||'',observer_name:raw.observer_name||'',
  warnings:raw.warnings||[],reviewed:false,payload:{teacher_id,observer_id:matchPerson(raw.observer_name,context.observers),
   academic_year:raw.academic_year||teacher?.academic_year||'',semester:raw.semester||'',visit_date:raw.visit_date||'',visit_type:'زيارة صفية',
   ...Object.fromEntries(['lesson_title','subject','class_section','lesson_period','student_count','absent_count','time_start','time_end','visit_number'].map(k=>[k,raw[k]??''])),status:'final'},
  ratings:Array.from({length:18},(_,i)=>({criterion_id:i+1,level:raw.ratings?.filter(r=>r.criterion_id===i+1).length===1?raw.ratings.find(r=>r.criterion_id===i+1).level:null})),
  details:{final_judgment:raw.final_judgment??'',judgment_basis:'',skills:raw.skills||[],skills_assessed:Boolean(raw.skills?.length),student_work:raw.student_work||[],work_assessed:Boolean(raw.student_work?.length),sample_count:raw.sample_count??'',successes:raw.successes||'',development:raw.development||'',support:raw.support||[],support_notes:raw.support_notes||''}};
}
export function validateProposal(item){
 const p=item.payload,d=item.details,errors=[];
 if(!p.teacher_id)errors.push('اختاري المعلمة من قائمة القسم المسموح.');
 if(!p.observer_id)errors.push('اختاري الزائرة من القائمة.');
 for(const[k,label]of[['visit_date','التاريخ'],['academic_year','العام الدراسي'],['semester','الفصل الدراسي'],['class_section','الصف والشعبة'],['lesson_title','عنوان الدرس']])if(!String(p[k]||'').trim())errors.push('أكملي '+label+'.');
 if(p.visit_date&&!/^\d{4}-\d{2}-\d{2}$/.test(p.visit_date))errors.push('راجعي صيغة التاريخ.');
 if(item.ratings.length!==18||item.ratings.some(r=>!Number.isInteger(Number(r.level))||Number(r.level)<1||Number(r.level)>4))errors.push('أكملي تقييم المعايير الثمانية عشر.');
 if(!d.final_judgment||!d.judgment_basis?.trim())errors.push('اختاري الحكم النهائي واكتبي مبرره وفق الاستمارة.');
 if(!item.reviewed)errors.push('أكدي مطابقة البيانات للاستـمارة الأصلية بعد المراجعة.');
 if(!item.pages?.length)errors.push('حددي صفحات الاستمارة.');
 if(item.invalidPages)errors.push('صححي أرقام صفحات الاستمارة.');
 if(p.time_start&&p.time_end&&p.time_end<=p.time_start)errors.push('نهاية الحصة يجب أن تكون بعد بدايتها.');
 if(p.student_count!==''&&p.absent_count!==''&&Number(p.absent_count)>Number(p.student_count))errors.push('عدد الغياب أكبر من عدد الطلبة.');
 if(d.support.includes(6)&&!d.support_notes.trim())errors.push('اكتبي توضيح أسلوب الدعم «أخرى».');
 return errors;
}
export function sameVisit(a,b){return a.teacher_id===b.teacher_id&&a.observer_id===b.observer_id&&a.visit_date===b.visit_date&&normalizeName(a.lesson_title)===normalizeName(b.lesson_title);}
export function bytesBase64(bytes){let s='';for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(s);}
