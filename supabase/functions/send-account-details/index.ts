import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
import nodemailer from 'npm:nodemailer@7.0.10';
const origin='https://hesaalfadhala-crypto.github.io';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json'};
const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers});
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('',{headers});
 if(req.method!=='POST')return reply(405,'طريقة غير مسموحة.');
 const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');
 if(!token)return reply(401,'سجلي الدخول أولًا.');
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error:authError}=await db.auth.getUser(token);
 if(authError||!user)return reply(401,'جلسة الدخول غير صالحة.');
 const {data:profile,error:profileError}=await db.from('profiles').select('role,school_access').eq('id',user.id).single();
 if(profileError||!profile||profile.school_access!=='all'||!['principal','assistant_principal'].includes(profile.role))return reply(403,'الإرسال متاح للمديرة وأ. حصه فقط.');
 let input;try{input=await req.json();}catch{return reply(400,'الطلب غير صالح.');}
 if(!/^[0-9a-f-]{36}$/i.test(input.operation_id||'')||!['test','teacher'].includes(input.mode))return reply(400,'الطلب غير صالح.');
 const sender=Deno.env.get('PORTAL_SMTP_USER'),smtpPassword=Deno.env.get('PORTAL_SMTP_PASSWORD'),initialPassword=Deno.env.get('PORTAL_INITIAL_PASSWORD');
 if(!sender||!smtpPassword||!initialPassword)return reply(503,'إعداد البريد غير مكتمل. احفظي أسرار البريد الثلاثة في Supabase أولًا.');
 let recipient=sender,recipientId=user.id,name='أ. حصه';
 if(input.mode==='teacher'){
  const {data:staff,error}=await db.from('weekly_staff').select('user_id,full_name,role_label').eq('id',input.staff_id).eq('active',true).single();
  if(error||!staff?.user_id||staff.role_label==='مديرة مساعدة')return reply(400,'اختاري معلمة مرتبطة بحساب موثّق.');
  const {data:targetProfile}=await db.from('profiles').select('role').eq('id',staff.user_id).single();
  if(!targetProfile||!['teacher','first_teacher','coordinator'].includes(targetProfile.role))return reply(400,'الحساب ليس حساب معلمة مخولة.');
  const {data:{user:target},error:targetError}=await db.auth.admin.getUserById(staff.user_id);
  if(targetError||!target?.email||!target.email_confirmed_at)return reply(400,'بريد الحساب غير موثّق.');
  recipient=target.email;recipientId=target.id;name=staff.full_name;
 }
 const {data:prior,error:priorError}=await db.from('account_email_deliveries').select('actor_id,recipient_id,status').eq('id',input.operation_id).maybeSingle();
 if(priorError)return reply(503,'تعذر قراءة سجل الإرسال.');
 if(prior){if(prior.actor_id!==user.id||prior.recipient_id!==recipientId)return reply(409,'معرف العملية مستخدم لطلب آخر.');return reply(prior.status==='accepted'?200:409,prior.status==='accepted'?'سبق قبول إرسال هذه الرسالة؛ لم تُكرر.':'سبق تنفيذ المحاولة. راجعي البريد وسجل الإرسال قبل المحاولة مجددًا.');}
 const {error:claimError}=await db.from('account_email_deliveries').insert({id:input.operation_id,actor_id:user.id,recipient_id:recipientId,mode:input.mode,rate_slot:Math.floor(Date.now()/300000),status:'pending'});
 if(claimError)return reply(claimError.code==='23505'?429:503,'تعذر بدء الإرسال؛ قد تكون أرسلتِ لهذا الحساب خلال آخر خمس دقائق.');
 const transport=nodemailer.createTransport({host:'smtp.gmail.com',port:465,secure:true,auth:{user:sender,pass:smtpPassword.replace(/\s/g,'')},connectionTimeout:15000,socketTimeout:20000});
 try{
  const text=`الأستاذة ${name}\nمرحبًا بكِ في بوابة أم كلثوم الذكية.\nرابط البوابة: https://hesaalfadhala-crypto.github.io/UmmKulthum-Smart-Portal/login.html\nبريد تسجيل الدخول: ${input.mode==='test'?'هذه رسالة اختبار فقط':recipient}\nكلمة المرور المؤقتة الموحدة: ${initialPassword}\nاحتفظي ببيانات الدخول لنفسكِ.\nمدرسة أم كلثوم الابتدائية الإعدادية للبنات`;
  const result=await transport.sendMail({from:{name:'بوابة أم كلثوم الذكية',address:sender},to:recipient,subject:input.mode==='test'?'اختبار إرسال بوابة أم كلثوم':'بيانات الدخول — بوابة أم كلثوم الذكية',text});
  if(!result.accepted?.length)throw new Error('Not accepted');
  const {error}=await db.from('account_email_deliveries').update({status:'accepted',finished_at:new Date().toISOString()}).eq('id',input.operation_id);
  return reply(error?202:200,error?'قبل Gmail الرسالة، لكن تعذر تحديث السجل. لا تعيدي الإرسال قبل مراجعة البريد.':'قبل Gmail إرسال الرسالة. يُتحقق من وصولها داخل صندوق البريد.');
 }catch{
  await db.from('account_email_deliveries').update({status:'uncertain',finished_at:new Date().toISOString()}).eq('id',input.operation_id);
  return reply(502,'تعذر تأكيد الإرسال. تحققي من كلمة مرور التطبيق والبريد قبل إعادة المحاولة.');
 }finally{transport.close();}
});
