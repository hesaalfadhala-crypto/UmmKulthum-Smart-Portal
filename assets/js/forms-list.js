async function loadSavedForms(){
 const box=document.getElementById('savedForms');
 try{
  const {data:{user},error:authError}=await supabaseClient.auth.getUser();
  if(authError||!user){location.replace('login.html');return;}
  let rows=[];for(let start=0;;start+=200){const {data,error}=await supabaseClient.from('forms').select('*').order('created_at',{ascending:false}).order('id',{ascending:false}).range(start,start+199);if(error)throw error;rows.push(...(data||[]));if(!data||data.length<200)break;}
  box.replaceChildren();
  for(const row of rows){const card=document.createElement('article');card.style.cssText='padding:20px;border-bottom:1px solid #eee';
   const title=document.createElement('h3');title.textContent=row.title;card.append(title);
   for(const value of [row.description,row.target_audience,'الحالة: '+(row.status==='draft'?'مسودة':row.status),row.closing_date?'تاريخ الإغلاق: '+row.closing_date:null])if(value){const line=document.createElement('p');line.textContent=value;card.append(line);}box.append(card);
  }
  if(!rows.length){const empty=document.createElement('p');empty.textContent='لا توجد نماذج محفوظة متاحة لحسابكِ.';box.append(empty);}
  const stats=[...document.querySelectorAll('.stats .stat')];
  stats[0].querySelector('span').textContent='النماذج المحفوظة';stats[0].querySelector('strong').textContent=rows.length;
  // Responses and participation do not exist yet: keep them explicitly unavailable.
  for(const card of stats.slice(1)){card.querySelector('strong').textContent='غير مفعّل';}
 }catch{box.textContent='تعذر تحميل النماذج. أعيدي المحاولة.';}
}
void loadSavedForms();
