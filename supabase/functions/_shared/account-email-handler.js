import {accountMessage,accountPassword,TEMPLATE_VERSION} from './account-email-template.js';
const headers={'Access-Control-Allow-Origin':'https://hesaalfadhala-crypto.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json'};
const validId=v=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v||'');
export function createAccountEmailHandler({createClient,nodemailer,env,now=()=>new Date()}){return async req=>{
 const reply=(status,message,extra={})=>new Response(JSON.stringify({message,...extra}),{status,headers});
 if(req.method==='OPTIONS')return new Response('',{headers});if(req.method!=='POST')return reply(405,'طريقة غير مسموحة.');
 const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');if(!token)return reply(401,'سجلي الدخول أولًا.');
 const url=env('SUPABASE_URL'),options={auth:{persistSession:false,autoRefreshToken:false}},db=createClient(url,env('SUPABASE_SERVICE_ROLE_KEY'),options),userDb=createClient(url,env('SUPABASE_ANON_KEY'),{...options,global:{headers:{Authorization:'Bearer '+token}}});
 const {data,error:authError}=await db.auth.getUser(token);if(authError||!data?.user)return reply(401,'جلسة الدخول غير صالحة.');const user=data.user;
 const {error:contextError}=await userDb.rpc('account_email_context');if(contextError)return reply(403,'الإرسال متاح للمديرة وحصه فقط.');
 let input;try{input=await req.json();}catch{return reply(400,'الطلب غير صالح.');}
 if(!validId(input.operation_id)||!['test','staff','teacher'].includes(input.mode))return reply(400,'الطلب غير صالح.');
 const mode=input.mode==='test'?'test':'teacher';let recipientId=user.id,recipient,email,password,batchId=null;
 const sender=env('PORTAL_SMTP_USER'),smtpPassword=env('PORTAL_SMTP_PASSWORD');if(!sender||!smtpPassword)return reply(503,'إعداد البريد غير مكتمل؛ لم يتم إرسال رسالة.');
 if(mode==='test'){
  if(!input.expected_test_recipient||String(input.expected_test_recipient).trim().toLowerCase()!==sender.trim().toLowerCase())return reply(409,'بريد اختبار الاستلام لا يطابق بريد المرسل المربوط. لم يتم الإرسال.');
  recipient=sender;email='[البريد الإلكتروني]';password='[كلمة المرور]';
 }else{
  if(!validId(input.batch_id))return reply(409,'الإرسال الجماعي متوقف حتى تأكيد وصول الاختبار والحصول على موافقة صريحة.');
  const {data:batch,error}=await db.from('account_email_batches').select('*').eq('id',input.batch_id).single();
  if(error||!batch||batch.approved_by!==user.id||batch.template_version!==TEMPLATE_VERSION||new Date(batch.expires_at)<=now()||!batch.receipt_confirmed_at)return reply(403,'الدفعة غير معتمدة لهذا الحساب أو انتهت صلاحيتها.');
  const {data:people,error:peopleError}=await userDb.rpc('account_email_recipients');if(peopleError)return reply(503,'تعذر مراجعة حسابات المستلمات.');
  let targetId=input.recipient_id;
  if(!targetId&&input.staff_id){const {data:staff}=await db.from('weekly_staff').select('user_id').eq('id',input.staff_id).eq('active',true).single();targetId=staff?.user_id;}
  if(!validId(targetId)||!batch.recipient_ids.includes(targetId))return reply(403,'المستلمة ليست ضمن الدفعة التي وافقتِ عليها.');
  const target=people.find(p=>p.id===targetId);if(!target)return reply(400,'حساب المستلمة لم يعد ضمن الحسابات الوزارية المعتمدة.');
  const initial=env('PORTAL_INITIAL_PASSWORD'),principal=env('PORTAL_PRINCIPAL_PASSWORD');
  try{if(batch.recipient_ids.some(id=>people.some(p=>p.id===id&&p.role==='principal')))accountPassword('principal',initial,principal);password=accountPassword(target.role,initial,principal);}catch(e){return reply(503,e.message+' لم يتم الإرسال.');}
  recipientId=target.id;recipient=target.email;email=target.email;batchId=batch.id;
 }
 if(batchId){const {data:existing,error}=await db.from('account_email_deliveries').select('id,status').eq('batch_id',batchId).eq('recipient_id',recipientId).maybeSingle();if(error)return reply(503,'تعذر مراجعة إرسال هذه المستلمة.');if(existing)return reply(existing.status==='accepted'?200:409,existing.status==='accepted'?'سبق قبول إرسال هذه المستلمة ضمن الدفعة؛ لم تُكرر.':'سبق بدء إرسال هذه المستلمة؛ تحققي من البريد أولًا.',{delivery_id:existing.id,recipient,status:existing.status});}
 const snapshot={mode,recipient_id:recipientId,recipient_email:recipient,batch_id:batchId,template_version:TEMPLATE_VERSION};
 const {data:prior,error:priorError}=await db.from('account_email_deliveries').select('actor_id,recipient_id,status,request_snapshot').eq('id',input.operation_id).maybeSingle();
 if(priorError)return reply(503,'تعذر قراءة سجل الإرسال.');if(prior){if(prior.actor_id!==user.id||prior.recipient_id!==recipientId||Object.keys(snapshot).some(k=>prior.request_snapshot?.[k]!==snapshot[k]))return reply(409,'معرف العملية مستخدم لطلب آخر.');return reply(prior.status==='accepted'?200:409,prior.status==='accepted'?'سبق قبول إرسال هذه الرسالة؛ لم تُكرر.':'سبق بدء المحاولة؛ تحققي من البريد قبل محاولة جديدة.',{delivery_id:input.operation_id,recipient,status:prior.status});}
 const {error:claimError}=await db.from('account_email_deliveries').insert({id:input.operation_id,actor_id:user.id,recipient_id:recipientId,recipient_email:recipient,mode,batch_id:batchId,template_version:TEMPLATE_VERSION,request_snapshot:snapshot,rate_slot:Math.floor(now().getTime()/300000),status:'pending'});
 if(claimError)return reply(claimError.code==='23505'?429:503,'تعذر بدء الإرسال. تحققي من سجل المحاولات قبل تكرار الطلب.');
 let transport;
 try{
  transport=nodemailer.createTransport({host:'smtp.gmail.com',port:465,secure:true,auth:{user:sender,pass:smtpPassword.replace(/\s/g,'')},connectionTimeout:15000,socketTimeout:20000});
  const result=await transport.sendMail({from:{name:'بوابة أم كلثوم الذكية',address:sender},to:recipient,subject:mode==='test'?'اختبار رسالة الترحيب — بوابة أم كلثوم الذكية':'بيانات تسجيل الدخول — بوابة أم كلثوم الذكية',...accountMessage(email,password)});
  if(!result.accepted?.some(address=>String(address).toLowerCase()===recipient.toLowerCase()))throw new Error('SMTP did not accept recipient');
  const {error}=await db.from('account_email_deliveries').update({status:'accepted',finished_at:now().toISOString()}).eq('id',input.operation_id);
  return reply(error?202:200,error?'قبل Gmail الرسالة، لكن تعذر تحديث السجل. تحققي من الوصول قبل أي محاولة أخرى.':'قبل Gmail الرسالة. يلزم تأكيد وصولها داخل صندوق البريد.',{delivery_id:input.operation_id,recipient,status:error?'uncertain':'accepted'});
 }catch{await db.from('account_email_deliveries').update({status:'uncertain',finished_at:now().toISOString()}).eq('id',input.operation_id);return reply(502,'تعذر تأكيد الإرسال؛ تحققي من البريد قبل إعادة المحاولة.',{delivery_id:input.operation_id,recipient,status:'uncertain'});}finally{transport?.close();}
};}
