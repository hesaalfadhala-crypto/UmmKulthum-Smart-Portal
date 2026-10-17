// Shared signature data for previews and both PDF formats. Legacy records stay untouched.
export const SUPERVISORS=[
 {id:'assistant',title:'بإشراف المديرة المساعدة',name:'أ. حصه سند الفضاله'},
 {id:'aisha',title:'بإشراف المديرة المساعدة',name:'أ. عايشة محمد يعقوب'},
 {id:'hiba',title:'بإشراف المديرة المساعدة',name:'أ. هبة علي حسين'},
 {id:'services',title:'بإشراف رئيسة الخدمات',name:'أ. حصه خليفة الظهراني'}
];
export function selectedSupervisors(d={}){
 if(Array.isArray(d.reportSupervisors))return SUPERVISORS.filter(s=>d.reportSupervisors.includes(s.id)).map(s=>s.id);
 if(SUPERVISORS.some(s=>s.id===d.reportSupervisor))return [d.reportSupervisor];
 const legacy=SUPERVISORS.filter(s=>(d.assistants||[]).includes(s.name)).map(s=>s.id);
 return legacy.length?legacy:['assistant'];
}
export function signatures(d={}) {
 const ids=selectedSupervisors(d),selected=SUPERVISORS.filter(s=>ids.includes(s.id));
 return [
  ['معدّة التقرير',String(d.reportPreparedBy||d.reportPreparer||d.executor||'—').trim()],
  ['',selected.map(s=>s.title+'\n'+s.name).join('\n')],
  ['مديرة المدرسة','أ. هيا محمد النعيمي']
 ];
}
export function renderSignatures(container,d) {
 container.replaceChildren();container.classList.add('report-signatures');container.dir='rtl';
 for(const [title,name] of signatures(d)){const box=document.createElement('div'),b=document.createElement('b'),p=document.createElement('p');b.textContent=title;p.textContent=name;box.append(b,p);container.append(box);}
}
export function drawSignatures(ctx,d,width,margin,top,size=24,font='Tahoma, Arial',draw=true){
 const col=(width-2*margin)/3,gap=18;ctx.direction='rtl';ctx.textAlign='center';
 const wrap=value=>{const lines=[];for(const paragraph of value.split('\n')){let line='';for(const word of paragraph.split(/\s+/)){for(const char of (line?' ':'')+word){if(line&&ctx.measureText(line+char).width>col-gap){lines.push(line);line='';}line+=char;}}if(line)lines.push(line);}return lines;};
 let height=0;signatures(d).forEach(([title,name],i)=>{let y=top;for(const [value,bold] of [[title,true],[name,false]]){ctx.font=(bold?'bold ':'')+size+'px '+font;const lines=wrap(value);if(draw){ctx.fillStyle='#174f4b';for(const line of lines){ctx.fillText(line,width-margin-col*(i+.5),y+size);y+=size*1.48;}}else y+=lines.length*size*1.48;y+=5;}height=Math.max(height,y-top);});ctx.textAlign='right';return height;
}
