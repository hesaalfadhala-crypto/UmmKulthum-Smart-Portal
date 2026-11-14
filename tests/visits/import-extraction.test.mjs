import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
test('extraction gateway authenticates, bounds requests and returns only complete validated output',async(t)=>{
 let handler,key='',allowed=true,logged=true,quota=false,sent;
 const client={auth:{getUser:async()=>({data:logged?{user:{id:'user'}}:null,error:logged?null:{}})},rpc:async name=>({error:!allowed||name==='claim_classroom_pdf_extraction'&&quota?{message:'quota exceeded'}:null}),from:()=>({select(){return this;},eq(){return this;},single:async()=>({data:{id:'batch'}})})};
 const oldFetch=globalThis.fetch,oldDeno=globalThis.Deno;
 globalThis.Deno={env:{get:n=>n==='OPENAI_API_KEY'?key:'https://example.test'},serve:fn=>handler=fn};globalThis.__pdfTestClient=client;
 try{
 let source=await fs.readFile(new URL('../../supabase/functions/extract-classroom-visits/index.ts',import.meta.url),'utf8');source=source.replace("import {createClient} from 'npm:@supabase/supabase-js@2.117.3';",'const createClient=()=>globalThis.__pdfTestClient;').replace("'./schema.js'",JSON.stringify(new URL('../../supabase/functions/extract-classroom-visits/schema.js',import.meta.url).href));
 await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
 const request=body=>new Request('https://example.test/extract',{method:'POST',headers:{Authorization:'Bearer test-user','Content-Type':'application/json'},body:JSON.stringify(body)});
 const body={batch_id:'00000000-0000-4000-8000-000000000001',page_count:2,pdf_base64:Buffer.from('%PDF-1.4\n').toString('base64')};
 await t.test('no credentials or permission never reaches provider',async()=>{assert.equal((await handler(new Request('https://example.test/extract',{method:'POST'}))).status,401);logged=false;assert.equal((await handler(request(body))).status,401);logged=true;allowed=false;assert.equal((await handler(request(body))).status,403);allowed=true;});
 await t.test('missing integration is explicit; originals are not sent',async()=>{const status=await handler(new Request('https://example.test/extract/status'));assert.deepEqual(await status.json(),{configured:false});const r=await handler(request(body));assert.equal(r.status,503);assert.equal((await r.json()).code,'EXTRACTION_NOT_CONFIGURED');});
 key='test-only-not-a-real-key';
 await t.test('malformed / oversized chunk and quota rejected',async()=>{assert.equal((await handler(request({...body,page_count:5}))).status,400);assert.equal((await handler(request({...body,pdf_base64:'not a pdf'}))).status,400);quota=true;assert.equal((await handler(request(body))).status,429);quota=false;});
 await t.test('provider timeout/incomplete/refusal never reports a completed extraction',async()=>{globalThis.fetch=async()=>new Response(JSON.stringify({status:'incomplete',output:[]}),{status:200});assert.equal((await handler(request(body))).status,502);globalThis.fetch=async()=>new Response(JSON.stringify({status:'completed',output:[{content:[{type:'refusal',refusal:'no'}]}]}),{status:200});assert.equal((await handler(request(body))).status,502);});
 await t.test('successful request uses strict schema, no storage and PDF; invalid pages rejected',async()=>{let pages=[1,2];globalThis.fetch=async(_url,init)=>{sent=JSON.parse(init.body);return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify({forms:[{pages}]})}]}]}),{status:200});};const result=await handler(request(body));assert.equal(result.status,200);assert.equal(sent.store,false);assert.equal(sent.text.format.strict,true);assert.equal(sent.input[0].content[1].type,'input_file');assert.match(sent.instructions,/لا تخمن/);pages=[9];assert.equal((await handler(request(body))).status,502);});
 }finally{globalThis.fetch=oldFetch;globalThis.Deno=oldDeno;delete globalThis.__pdfTestClient;}
});
