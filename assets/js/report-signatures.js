// Shared signature data for previews and both PDF formats. Legacy records stay untouched.
export function signatures(d={}) {
 const services=d.reportSupervisor==='services';
 return [
  ['معدّة التقرير',String(d.reportPreparedBy||d.executor||'—').trim()],
  [services?'بإشراف رئيسة الخدمات':'بإشراف المديرة المساعدة',services?'أ. حصه خليفة الظهراني':'أ. حصه سند الفضاله'],
  ['مديرة المدرسة','أ. هيا محمد النعيمي']
 ];
}
export function renderSignatures(container,d) {
 container.replaceChildren();container.classList.add('report-signatures');container.dir='rtl';
 for(const [title,name] of signatures(d)){const box=document.createElement('div'),b=document.createElement('b'),p=document.createElement('p');b.textContent=title;p.textContent=name;box.append(b,p);container.append(box);}
}
export function drawSignatures(ctx,d,width,margin,top,size=24,font='Tahoma, Arial',draw=true){
 const col=(width-2*margin)/3,gap=18;ctx.direction='rtl';ctx.textAlign='center';
 const wrap=value=>{const lines=[];let line='';for(const word of value.split(/\s+/)){for(const char of (line?' ':'')+word){if(line&&ctx.measureText(line+char).width>col-gap){lines.push(line);line='';}line+=char;}}lines.push(line);return lines;};
 let height=0;signatures(d).forEach(([title,name],i)=>{let y=top;for(const [value,bold] of [[title,true],[name,false]]){ctx.font=(bold?'bold ':'')+size+'px '+font;const lines=wrap(value);if(draw){ctx.fillStyle='#174f4b';for(const line of lines){ctx.fillText(line,width-margin-col*(i+.5),y+size);y+=size*1.48;}}else y+=lines.length*size*1.48;y+=5;}height=Math.max(height,y-top);});ctx.textAlign='right';return height;
}
