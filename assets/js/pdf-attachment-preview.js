import {downloadAttachment} from './pdf-attachments.js?v=20261023-embedded';
const ROOT='https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/';
let library;
async function renderer(){
 if(!library)library=import(ROOT+'build/pdf.min.mjs').then(pdf=>{pdf.GlobalWorkerOptions.workerSrc=ROOT+'build/pdf.worker.min.mjs';return pdf;}).catch(error=>{library=null;throw error;});
 return library;
}
// Render privately downloaded bytes locally; no document is sent to a rendering service.
export async function attachmentCanvases(files=[],{getRenderer=renderer,download=downloadAttachment,createCanvas=()=>document.createElement('canvas'),isCurrent=()=>true}={}){
 if(!files.length)return [];
 const pdfjs=await getRenderer(),canvases=[];
 for(const file of files){
  if(!isCurrent())return [];
  let task;
  try{
   const blob=await download(file);
   if(!isCurrent())return [];
   task=pdfjs.getDocument({data:new Uint8Array(await blob.arrayBuffer()),isEvalSupported:false,useSystemFonts:true,cMapUrl:ROOT+'cmaps/',cMapPacked:true,standardFontDataUrl:ROOT+'standard_fonts/'});
   const pdf=await task.promise;
   for(let number=1;number<=pdf.numPages;number++){
    if(!isCurrent())return [];
    const page=await pdf.getPage(number),base=page.getViewport({scale:1});
    const scale=Math.min(4.2,3508/Math.max(base.width,base.height));
    const viewport=page.getViewport({scale}),canvas=createCanvas();
    canvas.width=Math.ceil(viewport.width);canvas.height=Math.ceil(viewport.height);
    canvas.setAttribute?.('aria-label',file.name+' — الصفحة '+number+' من '+pdf.numPages);
    await page.render({canvasContext:canvas.getContext('2d'),viewport,background:'rgb(255,255,255)'}).promise;
    canvases.push(canvas);page.cleanup();
   }
  }catch(error){throw new Error('تعذر عرض صفحات المرفق '+file.name+'. قد يكون محميًا بكلمة مرور أو تالفًا، أو تعذر تحميل أداة العرض. أعيدي المحاولة.',{cause:error});}
  finally{await task?.destroy();}
 }
 return isCurrent()?canvases:[];
}
export async function showAttachmentPreviews(container,files=[],isCurrent=()=>true){
 container.replaceChildren();container.hidden=!files.length;
 for(const file of files){
  if(!isCurrent())return;
  const section=document.createElement('section'),title=document.createElement('h2'),body=document.createElement('div');
  title.textContent='المرفق: '+file.name;body.textContent='جار تحميل صفحات المرفق…';section.append(title,body);container.append(section);
  const render=async()=>{try{body.textContent='جار تحميل صفحات المرفق…';const pages=await attachmentCanvases([file],{isCurrent});if(!isCurrent())return;body.replaceChildren(...pages);}catch(error){if(!isCurrent())return;body.textContent=error.message;const retry=document.createElement('button');retry.type='button';retry.textContent='إعادة تحميل المرفق';retry.addEventListener('click',()=>void render());body.append(retry);}};
  await render();
 }
}
