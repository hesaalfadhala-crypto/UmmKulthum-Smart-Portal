// Shared signature data for previews and both PDF formats. Legacy records stay untouched.
export const SUPERVISORS=[
 {id:'assistant',title:'المديرة المساعدة',name:'أ. حصه سند الفضاله'},
 {id:'aisha',title:'المديرة المساعدة',name:'أ. عايشة محمد يعقوب'},
 {id:'hiba',title:'المديرة المساعدة',name:'أ. هبة علي حسين'},
 {id:'services',title:'رئيسة الخدمات',name:'أ. حصه خليفة الظهراني'}
];
export function selectedSupervisors(d={}){
 if(Array.isArray(d.reportSupervisors))return SUPERVISORS.filter(s=>d.reportSupervisors.includes(s.id)).map(s=>s.id);
 if(SUPERVISORS.some(s=>s.id===d.reportSupervisor))return [d.reportSupervisor];
 const legacy=SUPERVISORS.filter(s=>(d.assistants||[]).includes(s.name)).map(s=>s.id);
 return legacy.length?legacy:['assistant'];
}
export function supervisionGroups(d={}){
 const ids=selectedSupervisors(d),selected=SUPERVISORS.filter(s=>ids.includes(s.id));
 return {assistants:selected.filter(s=>s.id!=='services'),services:selected.find(s=>s.id==='services')};
}
export function signatures(d={}) {
 const {assistants,services}=supervisionGroups(d),body=[];
 if(assistants.length)body.push(assistants.length>1?'المديرات المساعدات':'المديرة المساعدة',assistants.map(s=>s.name).join(' • '));
 if(services)body.push('رئيسة الخدمات',services.name);
 return [['معدّة التقرير',String(d.reportPreparedBy||d.reportPreparer||d.executor||'—').trim()],[body.length?'بإشراف':'',body.join('\n')],['مديرة المدرسة','أ. هيا محمد النعيمي']];
}
export function renderSignatures(container,d) {
 container.replaceChildren();container.classList.add('report-signatures');container.dir='rtl';
 const data=signatures(d),groups=supervisionGroups(d);
 data.forEach(([title,name],i)=>{
  const box=document.createElement('div'),b=document.createElement('b');b.textContent=title;box.append(b);
  if(i!==1){const p=document.createElement('p');p.textContent=name;box.append(p);}
  else{box.className='supervision-signature';if(groups.assistants.length){const label=document.createElement('div'),names=document.createElement('div');label.className='supervision-role';label.textContent=groups.assistants.length>1?'المديرات المساعدات':'المديرة المساعدة';names.className='assistant-signature-names';for(const s of groups.assistants){const span=document.createElement('span');span.textContent=s.name;names.append(span);}box.append(label,names);}if(groups.services){const label=document.createElement('div'),p=document.createElement('p');label.className='supervision-role';label.textContent='رئيسة الخدمات';p.textContent=groups.services.name;box.append(label,p);}}
  container.append(box);
 });
}
export function drawSignatures(ctx,d,width,margin,top,size=24,font='Cairo, Tahoma, Arial',draw=true){
 const gap=20,total=width-2*margin,unit=(total-2*gap)/4.2,cw=unit*2.2,center=width/2;
 ctx.direction='rtl';ctx.textAlign='center';
 const lines=(value,max,bold=false)=>{ctx.font=(bold?'bold ':'')+(bold?24:22)+'px '+font;const out=[];for(const para of String(value).split('\n')){let line='';for(const word of para.split(/\s+/)){if(line&&ctx.measureText(line+' '+word).width>max){out.push(line);line=word;}else line+=(line?' ':'')+word;}out.push(line);}return out;};
 const text=(value,x,y,max,bold=false)=>{const ls=lines(value,max,bold);if(draw){ctx.fillStyle=bold?'#18574D':'#000000';for(let i=0;i<ls.length;i++)ctx.fillText(ls[i],x,y+(bold?24:22)+i*Math.ceil((bold?24:22)*1.7));}return ls.length*Math.ceil((bold?24:22)*1.7);};
 const data=signatures(d),groups=supervisionGroups(d);let height=0;
 for(const [i,x]of [[0,width-margin-unit/2],[2,margin+unit/2]]){let y=top;y+=text(data[i][0],x,y,unit,true)+12;y+=text(data[i][1],x,y,unit);height=Math.max(height,y-top);}
 let y=top;if(data[1][0])y+=text('بإشراف',center,y,cw,true)+12;
 if(groups.assistants.length){y+=text(groups.assistants.length>1?'المديرات المساعدات':'المديرة المساعدة',center,y,cw,true)+12;const sw=cw/groups.assistants.length;let h=0;groups.assistants.forEach((s,i)=>{h=Math.max(h,text(s.name,center+cw/2-sw*(i+.5),y,sw-12));});y+=h+6;}
 if(groups.services){y+=text('رئيسة الخدمات',center,y,cw,true)+12;y+=text(groups.services.name,center,y,cw);}
 ctx.textAlign='right';return Math.max(height,y-top);
}
