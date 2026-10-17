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
export function drawSignatures(ctx,d,width,margin,top,size=24,font='Tahoma, Arial',draw=true){
 const total=width-2*margin,gap=16,unit=(total-2*gap)/4.2,centerWidth=unit*2.2;
 const center=width/2,left=margin+unit/2,right=width-margin-unit/2;
 ctx.direction='rtl';ctx.textAlign='center';let height=0;
 const fit=(value,maxWidth,fontSize,bold)=>{let n=fontSize;ctx.font=(bold?'bold ':'')+n+'px '+font;while(ctx.measureText(value).width>maxWidth&&n>12){n-=.5;ctx.font=(bold?'bold ':'')+n+'px '+font;}return n;};
 const line=(value,x,y,maxWidth,fontSize,bold=false)=>{if(!value)return 0;const n=fit(value,maxWidth,fontSize,bold);if(draw){ctx.fillStyle='#174f4b';ctx.fillText(value,x,y+n);}return n*1.5;};
 const data=signatures(d),groups=supervisionGroups(d);
 for(const [i,x]of [[0,right],[2,left]]){let y=top;y+=line(data[i][0],x,y,unit,size*.9,true)+5;y+=line(data[i][1],x,y,unit,size*.85);height=Math.max(height,y-top);}
 let y=top;if(data[1][0])y+=line('بإشراف',center,y,centerWidth,size*.9,true)+5;
 if(groups.assistants.length){y+=line(groups.assistants.length>1?'المديرات المساعدات':'المديرة المساعدة',center,y,centerWidth,size*.76,true)+3;const slot=centerWidth/groups.assistants.length,namesSize=Math.min(...groups.assistants.map(s=>fit(s.name,slot-12,Math.min(18,size*.76),false)));let rowHeight=0;groups.assistants.forEach((s,i)=>{rowHeight=Math.max(rowHeight,line(s.name,center+centerWidth/2-slot*(i+.5),y,slot-12,namesSize));});y+=rowHeight+7;}
 if(groups.services){y+=line('رئيسة الخدمات',center,y,centerWidth,size*.76,true)+3;y+=line(groups.services.name,center,y,centerWidth,Math.min(18,size*.76));}
 ctx.textAlign='right';return Math.max(height,y-top);
}
