// A stalled local submission must never become a new server identity just to unlock the form.
export async function recoverDocumentationDraft(client,userId,pending,{editId=null,newRequestId=()=>crypto.randomUUID()}={}){
 if(!pending)return {kind:'editable'};
 let query=client.from('documentations').select('id,details,photo_files,attachment_files,edit_version,last_edit_request');
 query=editId?query.eq('id',editId):query.eq('created_by',userId).eq('request_id',pending.requestId);
 const {data,error}=await query.maybeSingle();
 if(error)throw Error('تعذر التحقق من محاولة الحفظ. المسودة وصورها محفوظة؛ أعيدي التحقق عند عودة الاتصال.');
 if(editId){
  if(!data)throw Error('تعذر فتح التقرير الأصلي أو انتهت صلاحية تعديله. المسودة باقية.');
  if(data.last_edit_request===pending.requestId)return {kind:'saved',row:data};
  if(data.edit_version!==pending.version)throw Object.assign(Error('تغير التقرير الأصلي. افتحي أحدث نسخة؛ المسودة باقية دون حذف.'),{recoveredReportId:data.id});
  return {kind:'editable',requestId:newRequestId(),verifyOriginalOnSave:false};
 }
 if(data)return {kind:'saved',row:data};
 return {kind:'editable',requestId:pending.requestId,verifyOriginalOnSave:true};
}
function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));return value;}
export function recoveredSubmissionMatches(expected,actual){return ['details','photo_files','attachment_files'].every(k=>JSON.stringify(canonical(expected[k]??(k==='details'?{}:[])))===JSON.stringify(canonical(actual[k]??(k==='details'?{}:[]))));}
