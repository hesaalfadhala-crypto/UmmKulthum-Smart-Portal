// Preserve entered paragraph boundaries in both documentation and saved report previews.
export function appendReportText(container,value){
 container.replaceChildren();
 String(value??'').replace(/\r\n?/g,'\n').split('\n').forEach(line=>{
  const p=document.createElement('span');p.className='report-paragraph';
  if(/^\s*[•●▪-]\s+/.test(line))p.classList.add('report-bullet');
  p.textContent=line||'\u00a0';container.append(p);
 });
}
