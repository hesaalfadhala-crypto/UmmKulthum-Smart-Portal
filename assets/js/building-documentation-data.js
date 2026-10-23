import {client,requireUser} from './portal-data.js?v=20261021-unified';
export {requireUser};
export async function listBuildingDocumentations(){await requireUser();const rows=[];for(let start=0;;start+=300){const {data,error}=await client.from('building_documentations').select('*').is('deleted_at',null).eq('is_test',false).order('created_at',{ascending:false}).range(start,start+299);if(error)throw Error('تعذر تحميل توثيقات متابعة المبنى المدرسي.');rows.push(...data);if(data.length<300)return rows;}}
export async function getBuildingDocumentation(id){const {data,error}=await client.from('building_documentations').select('*').eq('id',id).eq('is_test',false).maybeSingle();if(error||!data)throw Error('التقرير غير موجود أو لا تملكين صلاحية عرضه.');return data;}
export async function documentationRPC(name,args={}){const {data,error}=await client.rpc('building_'+name,args);if(error)throw Object.assign(Error(error.message),{code:error.code});return data;}
