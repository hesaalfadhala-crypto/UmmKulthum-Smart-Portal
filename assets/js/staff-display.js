// Job titles are display data, never authorization decisions.
const LEGACY_TITLES={principal:'مديرة المدرسة',assistant_principal:'المديرة المساعدة',coordinator:'منسقة',first_teacher:'معلمة أولى',teacher:'معلمة'};
export function staffTitle(profile={}){return profile.job_title!==undefined&&profile.job_title!==null?String(profile.job_title):LEGACY_TITLES[profile.role]||'';}
export function suggestDepartment(select,profile={}){if(select.value)return;const value=profile.departments?.[0]||profile.department||'';if(!value.trim())return;if(!Array.from(select.options).some(o=>o.value===value)){const option=select.ownerDocument.createElement('option');option.value=value;option.textContent=value;select.append(option);}select.value=value;}
