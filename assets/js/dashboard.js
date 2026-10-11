import {client,requireUser,fetchRecords,normalize} from './portal-data.js';
const message=document.getElementById('dashboardStatus');
const roles={principal:'مديرة المدرسة',assistant_principal:'مديرة مساعدة',coordinator:'منسقة',first_teacher:'معلمة أولى',teacher:'معلمة'};
const set=(id,value)=>document.getElementById(id).textContent=value;
document.getElementById('logout').addEventListener('click',async()=>{
 const button=document.getElementById('logout');button.disabled=true;
 try{const {error}=await client.auth.signOut({scope:'local'});if(error)throw error;location.replace('login.html');}
 catch{message.textContent='تعذر تسجيل الخروج. حاولي مرة أخرى.';button.disabled=false;}
});
async function load(){
 try{
  const user=await requireUser();
  const {data:profile,error}=await client.from('profiles').select('full_name,role,department,school_access').eq('id',user.id).single();
  if(error||!profile)throw new Error('تعذر قراءة صلاحيات الحساب.');
  set('userName',profile.full_name||'');set('userRole',roles[profile.role]||profile.role||'');
  set('sidebarUser',profile.full_name+' · '+(roles[profile.role]||''));
  const records=await fetchRecords(),data=records.map(r=>normalize(r).data);
  set('stat-total',records.length);set('stat-saved',records.length);
  set('stat-projects',records.filter(r=>normalize(r).data.projects.length||r.activity_type==='مبادرة').length);
  set('stat-workshops',data.filter(d=>d.type==='ورشة تدريبية').length);
  message.textContent='تم تحديث المؤشرات من الأرشيف المتاح لحسابكِ';
 }catch(error){
  if(error.message.includes('تسجيل الدخول')){location.replace('login.html');return;}
  ['total','saved','projects','workshops'].forEach(key=>set('stat-'+key,'—'));message.textContent=error.message;
 }
}
void load();
