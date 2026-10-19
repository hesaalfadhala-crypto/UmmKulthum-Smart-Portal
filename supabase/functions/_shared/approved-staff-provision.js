// Temporary, explicitly approved provisioning. Secrets are read only inside the server.
export function approvedStaffProvision({createClient,env,manifest,tokenHash,batchId,expires,now=()=>Date.now()}){
 const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 return async req=>{if(req.method!=='POST')return reply(405,{error:'method_not_allowed'});if(now()>expires)return reply(410,{error:'operation_closed'});
 let input;try{const raw=await req.text();if(raw.length>1000)return reply(400,{error:'invalid_request'});input=JSON.parse(raw);}catch{return reply(400,{error:'invalid_request'});}
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(String(input.token||''))))).map(b=>b.toString(16).padStart(2,'0')).join('');if(hash!==tokenHash)return reply(403,{error:'forbidden'});
 if(manifest.length!==3||new Set(manifest.map(t=>t.email.toLowerCase())).size!==3||manifest.some(t=>!t.email.toLowerCase().endsWith('@moe.bh')||!t.full_name||t.role!=='teacher'))return reply(409,{error:'review_manifest'});
 const password=env('PORTAL_INITIAL_PASSWORD');if(!password)return reply(503,{error:'secure_initial_password_missing'});
 const url=env('SUPABASE_URL'),options={auth:{persistSession:false,autoRefreshToken:false}},admin=createClient(url,env('SUPABASE_SERVICE_ROLE_KEY'),options);
 const users=[];for(let page=1;;page++){const {data,error}=await admin.auth.admin.listUsers({page,perPage:200});if(error)return reply(503,{error:'account_check_failed'});users.push(...data.users);if(data.users.length<200)break;}
 for(const target of manifest){const existing=users.filter(u=>u.email?.toLowerCase()===target.email.toLowerCase());if(existing.length>1||existing.some(u=>u.app_metadata?.portal_provision_batch!==batchId))return reply(409,{error:'existing_account_requires_review'});}
 const results=[];for(const target of manifest){let user=users.find(u=>u.email?.toLowerCase()===target.email.toLowerCase()),created=false;
 if(!user){const {data,error}=await admin.auth.admin.createUser({email:target.email.toLowerCase(),password,email_confirm:true,user_metadata:{full_name:target.full_name,job_title:target.job_title,department:target.department},app_metadata:{portal_provision_batch:batchId}});if(error||!data?.user)return reply(503,{error:'creation_incomplete',completed:results});user=data.user;created=true;}
 // Only accounts tagged by this operation can reach this upsert; existing school accounts are excluded above.
 const {error}=await admin.from('profiles').upsert({id:user.id,full_name:target.full_name,job_title:target.job_title,department:target.department,departments:target.departments,role:'teacher',school_access:'own'},{onConflict:'id'});if(error)return reply(503,{error:'profile_incomplete',completed:results});
 const test=createClient(url,env('SUPABASE_ANON_KEY'),options),signed=await test.auth.signInWithPassword({email:target.email.toLowerCase(),password});const login_verified=!signed.error&&signed.data?.user?.id===user.id;if(login_verified)await test.auth.signOut({scope:'local'});
 results.push({email:target.email.toLowerCase(),user_id:user.id,created,login_verified});if(!login_verified)return reply(503,{error:'login_test_failed',completed:results});}
 return reply(200,{results,email_sent:false});
 };
}
