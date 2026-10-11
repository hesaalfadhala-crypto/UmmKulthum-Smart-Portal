const key=(user,kind)=>'ummkulthum-support:'+user+':'+kind;
export function read(user,kind){try{const raw=window.localStorage.getItem(key(user,kind));return raw?JSON.parse(raw):null;}catch{throw new Error('تعذر استرجاع مسودة الطلب على هذا الجهاز.');}}
export function write(user,kind,value){try{window.localStorage.setItem(key(user,kind),JSON.stringify(value));}catch{throw new Error('تعذر تثبيت محاولة الحفظ على هذا الجهاز. أبقي النموذج مفتوحًا حتى تُحفظ بياناته.');}}
export function remove(user,kind){window.localStorage.removeItem(key(user,kind));}
