import {client,element} from './portal-data.js';
export async function installAchievementReview(row){
 const {data:ctx,error}=await client.rpc('achievement_report_context',{report_id:row.id});if(error||!ctx?.can_review)return;
 const box=element('section',undefined,'achievement-review no-print');box.style.cssText='padding:16px;margin:16px 0;border:1px solid #cddcd7;background:#f4f8f5';
 box.append(element('h2','احتساب التقرير في لوحة الإنجاز والتميز'));const message=element('p');box.append(message);
 const refresh=c=>{message.textContent=c.state==='automatic'?'يُحتسب تلقائيًا إذا كان ضمن الفترة المحددة؛ تُستبعد النسخ المتطابقة.':c.state==='excluded'?'مستبعد من المنافسة، مع الاحتفاظ بالتقرير.':'غير مستوفٍ لشروط الاحتساب.';if(!c.complete)message.textContent+=' التقرير غير مكتمل.';if(c.test_record)message.textContent+=' توجد علامة بيانات تجريبية.';};refresh(ctx);
 const note=element('input');note.placeholder='سبب الاستبعاد عند الحاجة';note.maxLength=500;note.setAttribute('aria-label','سبب الاستبعاد');box.append(note);
 const approve=element('button','إلغاء الاستبعاد واحتساب التقرير تلقائيًا'),exclude=element('button','استبعاد من المنافسة دون حذف');approve.type=exclude.type='button';approve.disabled=!ctx.complete||ctx.test_record||ctx.deleted;exclude.disabled=ctx.deleted;
 for(const [button,decision]of [[approve,'approved'],[exclude,'excluded']])button.addEventListener('click',async()=>{if(decision==='excluded'&&!note.value.trim()){message.textContent='اكتبي سبب الاستبعاد أولًا.';return;}approve.disabled=exclude.disabled=true;try{const {data,error}=await client.rpc('review_achievement_report',{report_id:row.id,decision,expected_version:ctx.version,note:note.value.trim()});if(error)throw error;refresh(data);}catch(e){message.textContent=e.message;}finally{approve.disabled=!ctx.complete||ctx.test_record||ctx.deleted;exclude.disabled=ctx.deleted;}});
 box.append(approve,exclude);const a=element('a',' فتح لوحة الإنجاز والتميز');a.href='achievements.html';box.append(a);document.querySelector('.toolbar').after(box);
}
