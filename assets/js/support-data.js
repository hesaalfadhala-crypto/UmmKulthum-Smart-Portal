import {supportReports} from './documentation-choices.js?v=20261021-recognition';
import {client,requireUser,fetchRecords} from './portal-data.js';
export {client};
export async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error){const messages={'40001':'تم تعديل الطلب من جلسة أخرى. حدّثي القائمة ثم أعيدي المراجعة.','42501':'ليست لديكِ صلاحية لهذا الإجراء، أو يلزم تسجيل الدخول بحساب معتمد.','23P01':'الموعد يتعارض مع حجز أو ورشة معتمدة. اختاري موعدًا آخر.'};const e=new Error(messages[error.code]||error.message||'تعذر تنفيذ الإجراء. بياناتكِ باقية لإعادة المحاولة.');e.code=error.code;e.definitive=!!error.code;throw e;}return data;}
export async function context(){const user=await requireUser();let ctx;try{ctx=await rpc('support_center_context');}catch{throw new Error('تعذر تحميل صلاحيات مركز الدعم. قد يكون التفعيل لم يكتمل بعد؛ حاولي التحديث.');}return {...ctx,user};}
export async function rows(table,order='created_at'){const out=[];for(let start=0;;start+=200){const {data,error}=await client.from(table).select('*').order(order,{ascending:false}).order('id').range(start,start+199);if(error)throw new Error('تعذر تحميل بيانات المركز. تحققي من الاتصال وحدّثي الصفحة.');out.push(...(data||[]));if(!data||data.length<200)return out;}}
export async function workshops(){return supportReports(await fetchRecords());}
export async function load(){const [requests,programs,reports,impacts,summary]=await Promise.all([rows('support_requests'),rows('support_programs','starts_at'),workshops(),rows('support_impacts'),rpc('support_center_summary_filtered')]);return {requests,programs,reports,impacts,summary};}
export async function sameUser(expected){const user=await requireUser();if(user.id!==expected)throw new Error('تغيّر حساب الدخول. أعيدي تحميل الصفحة قبل الحفظ.');}
export function node(tag,text,cls){const n=document.createElement(tag);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n;}
export function option(select,value,label){const o=node('option',label);o.value=value;select.append(o);}
export const STATUS={pending:'قيد المراجعة',approved:'معتمد',declined:'مرفوض',cancelled:'ملغى',completed:'منفذ',needs_revision:'مطلوب تعديل الموعد'};
export const AUDIENCE={teachers:'الهيئة التعليمية',admins:'الهيئة الإدارية',students:'الطالبات'};
export function date(value,withTime=false){if(!value)return 'غير محدد';return new Intl.DateTimeFormat('ar-BH',{timeZone:'Asia/Bahrain',dateStyle:'medium',...(withTime?{timeStyle:'short'}:{})}).format(new Date(value));}
export function schoolDate(value=new Date()){const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bahrain',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(value));const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));return p.year+'-'+p.month+'-'+p.day;}
