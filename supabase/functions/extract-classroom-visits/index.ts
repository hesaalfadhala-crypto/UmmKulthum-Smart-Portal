import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
import {extractionSchema,extractionInstructions} from './schema.js';
const allowedOrigin='https://hesaalfadhala-crypto.github.io';
const cors={'Access-Control-Allow-Origin':allowedOrigin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Vary':'Origin'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 // Public readiness contains no user data or key. All extraction remains authenticated below.
 if(req.method==='GET'&&new URL(req.url).pathname.endsWith('/status'))return reply({configured:Boolean(Deno.env.get('OPENAI_API_KEY'))});
 if(req.method!=='POST')return reply({error:'طريقة غير مسموحة'},405);
 if(req.headers.get('origin')&&req.headers.get('origin')!==allowedOrigin)return reply({error:'مصدر غير مسموح'},403);
 const token=req.headers.get('Authorization');
 if(!token?.startsWith('Bearer '))return reply({error:'يرجى تسجيل الدخول'},401);
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:token}},auth:{persistSession:false}});
 const {data:user,error:authError}=await client.auth.getUser();
 if(authError||!user?.user)return reply({error:'انتهت الجلسة. أعيدي تسجيل الدخول.'},401);
 const {error:accessError}=await client.rpc('classroom_import_context');
 if(accessError)return reply({error:'لا توجد صلاحية لاستيراد الزيارات'},403);
 try{
  if(Number(req.headers.get('content-length')||0)>14000000)return reply({error:'جزء الملف كبير جدًا'},413);
  const bodyText=await req.text();
  if(bodyText.length>14000000)return reply({error:'جزء الملف كبير جدًا'},413);
  const body=JSON.parse(bodyText);
  const key=Deno.env.get('OPENAI_API_KEY');
  if(body.action==='status')return reply({configured:Boolean(key)});
  if(!key)return reply({error:'الاستخراج التلقائي بانتظار تفعيل خدمة قراءة PDF من إدارة البوابة.',code:'EXTRACTION_NOT_CONFIGURED'},503);
  if(!/^[a-f0-9-]{36}$/i.test(body.batch_id)||!Number.isInteger(body.page_count)||body.page_count<1||body.page_count>4||typeof body.pdf_base64!=='string'||body.pdf_base64.length>13000000||!body.pdf_base64.startsWith('JVBERi0')||!/^[A-Za-z0-9+/=]+$/.test(body.pdf_base64))return reply({error:'جزء PDF غير صالح'},400);
  const {data:batch,error:batchError}=await client.from('classroom_import_batches').select('id').eq('id',body.batch_id).single();
  if(batchError||!batch)return reply({error:'الملف غير متاح'},403);
  const {error:limitError}=await client.rpc('claim_classroom_pdf_extraction',{batch:body.batch_id});
  if(limitError)return reply({error:limitError.message},429);
  const response=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{'Authorization':`Bearer ${key}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(120000),body:JSON.stringify({
   model:Deno.env.get('CLASSROOM_PDF_MODEL')||'gpt-4.1-mini-2025-04-14',store:false,max_output_tokens:14000,
   instructions:extractionInstructions,
   input:[{role:'user',content:[{type:'input_text',text:`استخرج استمارات الزيارة في هذا الجزء المكون من ${body.page_count} صفحات.`},{type:'input_file',filename:'classroom-visits.pdf',file_data:`data:application/pdf;base64,${body.pdf_base64}`}]}],
   text:{format:{type:'json_schema',name:'classroom_visit_forms',strict:true,schema:extractionSchema}}
  })});
  if(!response.ok)return reply({error:response.status===429?'خدمة القراءة مشغولة أو رصيدها غير متاح. أعيدي المحاولة لاحقًا.':'تعذر قراءة الملف تلقائيًا. راجعي اتصال خدمة القراءة مع إدارة البوابة.'},502);
  const result=await response.json();
  if(result.status!=='completed')return reply({error:'لم تكتمل القراءة. قسمي الملف إلى أجزاء أصغر ثم أعيدي المحاولة.'},502);
  const output=result.output?.flatMap((x:any)=>x.content||[]).filter((x:any)=>x.type==='output_text').map((x:any)=>x.text).join('');
  const extracted=JSON.parse(output||'{}');
  if(!Array.isArray(extracted.forms)||extracted.forms.length>4||extracted.forms.some((x:any)=>!Array.isArray(x.pages)||!x.pages.length||x.pages.some((p:number)=>!Number.isInteger(p)||p<1||p>body.page_count)))return reply({error:'تعذر التحقق من صفحات الاستمارات. لم تحفظ أي زيارة.'},502);
  return reply(extracted);
 }catch(e){return reply({error:e instanceof Error&&e.name==='TimeoutError'?'استغرقت القراءة وقتًا طويلًا. أعيدي المحاولة؛ لم تحفظ أي زيارة.':'تعذر إكمال قراءة الملف. لم تحفظ أي زيارة.'},500);}
});
