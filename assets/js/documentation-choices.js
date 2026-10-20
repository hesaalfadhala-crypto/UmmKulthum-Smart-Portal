export const SUPPORT_CENTER='مركز الدعم والتطوير المهني';
export const OTHER_FIELDS={type:'نوع الفعالية',department:'القسم',projects:'المشروع أو المبادرة',committees:'اللجنة',targets:'الفئة المستهدفة',docCompetitionResult:'نتيجة المسابقة'};
export function resolveOther(value,key,details={}){const text=details.otherDetails?.[key]?.trim();const one=v=>v==='أخرى'&&text?text:v;return Array.isArray(value)?value.map(one):one(value);}
export function displayChoices(d){const copy={...d};for(const key of Object.keys(OTHER_FIELDS))if(key in copy)copy[key]=resolveOther(copy[key],key,d);return copy;}
export function validateOtherChoices(d){for(const [key,label] of Object.entries(OTHER_FIELDS)){if(key==='targets'&&d.recognition?.schemaVersion===2&&d.projects?.includes('أنتِ تستحقين الشكر'))continue;if(key==='docCompetitionResult'&&d.type!=='مسابقة وإنجاز طلابي')continue;const selected=Array.isArray(d[key])?d[key].includes('أخرى'):d[key]==='أخرى';if(selected&&(!d.otherDetails?.[key]?.trim()||d.otherDetails[key].trim().length>300))throw new Error('يرجى التحديد: '+label+' (حتى 300 حرف).');}}
export function isCenterReport(r){return (r.department||r.details?.department)===SUPPORT_CENTER;}
export function isWorkshop(r){return (r.activity_type||r.details?.type)==='ورشة تدريبية';}
export function supportReports(records){return [...new Map(records.filter(r=>!r.deleted_at&&(isWorkshop(r)||isCenterReport(r))).map(r=>[String(r.id),r])).values()];}
export function installOtherChoices(form){
 const controls=new Map();
 for(const [key,label] of Object.entries(OTHER_FIELDS)){
  const selector={projects:'.project-checks',committees:'.committee-checks',targets:'.target-checks'}[key];
  const source=selector?form.querySelector(selector):form.querySelector('#'+key);if(!source)continue;
  const wrap=document.createElement('div');wrap.className='field';wrap.hidden=true;
  const caption=document.createElement('label'),input=document.createElement('input');input.id=key+'Other';input.type='text';input.maxLength=300;input.setAttribute('aria-label','يرجى التحديد — '+label);caption.htmlFor=input.id;caption.textContent='يرجى التحديد';wrap.append(caption,input);source.after(wrap);
  const selected=()=>{if(key==='docCompetitionResult'&&form.querySelector('#type')?.value!=='مسابقة وإنجاز طلابي')return false;return selector?!!source.querySelector('input[value="أخرى"]:checked'):source.value==='أخرى';};
  const update=()=>{wrap.hidden=!selected();input.required=selected();};source.addEventListener('change',update);source.addEventListener('input',update);controls.set(key,{input,update,selected});update();
 }
 return {update(){for(const c of controls.values())c.update();},collect(d){d.otherDetails={};for(const [key,c]of controls)if(c.selected())d.otherDetails[key]=c.input.value.trim();return d;},restore(d){for(const [key,c]of controls){c.input.value=d.otherDetails?.[key]||d[key+'Other']||'';c.update();}}};
}
