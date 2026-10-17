import {databaseRecord,preparePhoto,PHOTO_BUCKET} from './save-documentation.js';
import {validateOtherChoices} from './documentation-choices.js';
import {validateNewDetails} from './recognition-model.js';

export async function editContext(client,id){
 const {data,error}=await client.rpc('report_edit_context',{report_id:id});
 if(error)throw new Error('تعذر التحقق من صلاحية التعديل. أعيدي المحاولة.');
 return data||{can_edit:false};
}
export function editableData(row,normalized){
 const raw=row.details||{},data={...normalized.data,...raw};
 // Retain canonical Other selections, not their rendered labels, when reopening the form.
 for(const k of ['department','type','projects','committees','targets'])if(raw[k]!==undefined)data[k]=raw[k];
 return data;
}
export async function saveReportEdit(client,userId,edit,checkpoint,progress=()=>{}){
 validateOtherChoices(edit.data);validateNewDetails(edit.data);
 if(!edit.data.activity?.trim())throw new Error('اكتبي اسم الفعالية أو النشاط.');
 const lookup=async()=>{const {data,error}=await client.from('documentations').select('id,edit_version,last_edit_request').eq('id',edit.id).single();if(error||!data)throw new Error('تعذر التحقق من حفظ التعديل. بياناتك باقية في المسودة.');return data;};
 let current=await lookup();if(current.last_edit_request===edit.requestId)return current;
 if(current.edit_version!==edit.version)throw new Error('تغير التقرير لدى مستخدمة أخرى. افتحي أحدث نسخة قبل متابعة التعديل؛ مسودتك باقية.');
 if(!(await editContext(client,edit.id)).can_edit)throw new Error('ليست لديكِ صلاحية تعديل هذا التقرير.');
 edit.uploaded||=[];edit.uploadedAttachments||=[];
 if(edit.retainedPhotos.length+edit.files.length>10)throw new Error('الحد الأقصى 10 صور، ويشمل الصور السابقة.');
 if(edit.retainedAttachments.length+(edit.attachments||[]).length>5)throw new Error('الحد الأقصى 5 مرفقات PDF، ويشمل المرفقات السابقة.');
 for(let i=edit.uploaded.length;i<edit.files.length;i++){
  progress('جار حفظ الصورة الجديدة '+(i+1)+'…');const f=edit.files[i],p=await preparePhoto(f),path=userId+'/'+edit.requestId+'/'+crypto.randomUUID()+'.jpg';
  const {error}=await client.storage.from(PHOTO_BUCKET).upload(path,p.blob,{contentType:'image/jpeg',upsert:false});
  if(error)throw new Error('تعذر حفظ الصورة الجديدة. أعيدي محاولة الحفظ بنفس المسودة.');
  edit.uploaded.push({bucket:PHOTO_BUCKET,path,name:f.name,size:p.blob.size,width:p.width,height:p.height});await checkpoint();
 }
 for(let i=edit.uploadedAttachments.length;i<(edit.attachments||[]).length;i++){
  const f=edit.attachments[i];if(f.size<1||f.size>8388608||String.fromCharCode(...new Uint8Array(await f.slice(0,5).arrayBuffer()))!=='%PDF-')throw new Error('اختاري ملف PDF صالحًا حتى 8 ميغابايت.');
  const path=userId+'/'+edit.requestId+'/'+crypto.randomUUID()+'.pdf';const {error}=await client.storage.from('school-report-files').upload(path,f,{contentType:'application/pdf',upsert:false});
  if(error)throw new Error('تعذر حفظ المرفق الجديد. أعيدي محاولة الحفظ.');
  edit.uploadedAttachments.push({bucket:'school-report-files',path,name:f.name,size:f.size});await checkpoint();
 }
 const payload=databaseRecord(userId,{requestId:edit.requestId,data:edit.data,uploaded:[...edit.retainedPhotos,...edit.uploaded],uploadedAttachments:[...edit.retainedAttachments,...edit.uploadedAttachments]});
 delete payload.created_by;delete payload.request_id;payload.last_edit_request=edit.requestId;
 edit.sent=true;await checkpoint();progress('جار تحديث التقرير الأصلي…');
 try{
  const {data,error}=await client.from('documentations').update(payload).eq('id',edit.id).eq('edit_version',edit.version).select('id,edit_version,last_edit_request').single();
  if(error||!data)throw error||new Error('لم يتأكد حفظ التعديل.');return data;
 }catch(e){current=await lookup();if(current.last_edit_request===edit.requestId)return current;
  if(current.edit_version!==edit.version)throw new Error('حُفظ تعديل آخر على التقرير. افتحي أحدث نسخة؛ مسودتك باقية.');
  edit.sent=false;await checkpoint();
  throw new Error('لم يُحفظ التعديل: '+(e?.message||'تحققي من الاتصال وأعيدي المحاولة بنفس المسودة.'));
 }
}
