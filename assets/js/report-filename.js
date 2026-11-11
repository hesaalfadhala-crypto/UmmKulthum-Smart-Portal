// Only download metadata is changed; report identifiers and contents are untouched.
export function safeReportTitle(value) {
  let title=String(value??'').normalize('NFC').replace(/[\\/:*?"<>|\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g,' ').replace(/\s+/g,' ').replace(/^[. ]+|[. ]+$/g,'').replace(/\.pdf$/i,'').trim();
  if(!title)title='تقرير';
  if(/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(title))title='تقرير '+title;
  // Leave room for extensions and suffixes within common 255-byte filesystem limits.
  while(new TextEncoder().encode(title).length>180)title=Array.from(title).slice(0,-1).join('');
  return title.trim();
}
export function reportTitle(record={}) {return record.data?.activity||record.activity||record.title||record.subtitle||'تقرير';}
export function reportFilename(record={},used,duplicate=false) {
  const base=safeReportTitle(reportTitle(record));
  // Add the report identifier only when a title collides.
  const id=record.id??record.reference??record.document?.id;
  const suffix=id!=null&&String(id).trim()?' - '+safeReportTitle(id):'';
  let name=base+'.pdf',n=2;
  if(duplicate||used?.has(name.toLocaleLowerCase()))name=base+suffix+'.pdf';
  while(used?.has(name.toLocaleLowerCase()))name=base+suffix+' ('+(n++)+').pdf';
  used?.add(name.toLocaleLowerCase());return name;
}
export function saveReportPDF(bytes,record) {
  const blob=bytes instanceof Blob?bytes:new Blob([bytes],{type:'application/pdf'});
  const token=(window.name.startsWith('report-download:')?window.name.slice(16):'');
  if(token&&window.parent!==window&&typeof window.parent.collectReportPDF==='function'){
    window.parent.collectReportPDF(window,token,blob,record);return;
  }
  const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=downloadFilename(record);a.click();setTimeout(()=>URL.revokeObjectURL(url),30000);
}

function downloadFilename(record){
  const key='ummkulthum-report-download-names',base=safeReportTitle(reportTitle(record)).toLocaleLowerCase(),id=String(record.id??record.reference??'');
  try{const registry=JSON.parse(localStorage.getItem(key)||'{}'),duplicate=Object.hasOwn(registry,base)&&registry[base]!==id;registry[base]=id;const recent=Object.fromEntries(Object.entries(registry).slice(-500));localStorage.setItem(key,JSON.stringify(recent));return reportFilename(record,undefined,duplicate);}catch{return reportFilename(record);}
}
