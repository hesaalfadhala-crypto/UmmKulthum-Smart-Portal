import {CRITERIA,EXCHANGE_TITLE,visitRows} from './exchange-visit-model.js';
import {drawSignatures} from './report-signatures.js?v=20261021-spacing';
// A4 table renderer. Split long cells into bordered continuation rows; never shrink text.
export function exchangeCanvases(record,{createCanvas,logo,photos=[]}){
 const W=1240,H=1754,M=60,R=W-M,WIDTH=W-2*M,LIMIT=1620,SIZE=22,LH=29,FONT='"Cairo",Tahoma,Arial',d=record.data,v=d.exchangeVisit||{};
 const measure=createCanvas(W,H).getContext('2d');
 function wrap(value,width,bold=false){measure.font=(bold?'bold ':'')+SIZE+'px '+FONT;const lines=[];for(const para of String(value??'—').split('\n')){let line='';for(const word of para.split(/\s+/)){if(measure.measureText(word).width>width){if(line){lines.push(line);line='';}let part='';for(const ch of word){if(part&&measure.measureText(part+ch).width>width){lines.push(part);part=ch;}else part+=ch;}line=part;continue;}const next=line?line+' '+word:word;if(line&&measure.measureText(next).width>width){lines.push(line);line=word;}else line=next;}lines.push(line);}return lines;}
 const blocks=[];
 function row(cells,widths,bold=[]){const lines=cells.map((c,i)=>wrap(c,widths[i]-20,bold.includes(i)));const total=Math.max(...lines.map(l=>l.length));for(let offset=0;offset<total;offset+=25){const slices=lines.map(l=>l.slice(offset,offset+25));blocks.push({cells:slices,widths,bold,height:Math.max(...slices.map(l=>l.length),1)*LH+10});}}
 for(const values of visitRows(d))row(values,[180,380,180,380],[0,2]);
 blocks.push({gap:12,height:12});const criterionHead=()=>row(['عناصر الدرس','معايير الملاحظة','✓'],[220,840,60],[0,1,2]);criterionHead();
 let previousDomain='';for(const c of CRITERIA){row([c.domain===previousDomain?'':c.domain,c.text,(v.selected||[]).includes(c.id)?'✓':'□'],[220,840,60]);blocks.at(-1).criterion=true;previousDomain=c.domain;}
 blocks.push({gap:12,height:12});row(['أبرز الممارسات المستفادة من الزيارة'],[WIDTH],[0]);row([v.practices||''],[WIDTH]);row(['المعلمة الزائرة',v.visitorName||d.executor,'المعلمة الأولى أو المنسقة',v.coordinatorName],[180,380,240,320],[0,2]);row(['متابعة المديرة المساعدة',v.followUp],[280,840],[0]);
 const sh=drawSignatures(measure,d,W,M,0,SIZE,FONT,false)+24;blocks.push({signature:true,height:sh});
 for(const [i,img]of photos.entries())blocks.push({image:img,label:'الصورة '+(i+1),height:530});
 const groups=[];let group=[],used=0;const top=index=>index?130:210;
 for(const block of blocks){if(used+block.height>LIMIT-top(groups.length)&&group.length){groups.push(group);group=[];used=0;}
 if(block.height>LIMIT-top(groups.length))throw Error('تعذر توزيع الجدول دون قص.');group.push(block);used+=block.height;}
 if(group.length)groups.push(group);
 return groups.map((items,index)=>{const canvas=createCanvas(W,H),g=canvas.getContext('2d');g.fillStyle='#fff';g.fillRect(0,0,W,H);g.direction='rtl';g.textAlign='right';g.textBaseline='alphabetic';
 if(!index){const scale=Math.min(WIDTH/logo.width,95/logo.height);g.drawImage(logo,(W-logo.width*scale)/2,25,logo.width*scale,logo.height*scale);g.fillStyle='#18574D';g.font='bold 32px '+FONT;g.textAlign='center';g.fillText(EXCHANGE_TITLE,W/2,170);g.textAlign='right';}else{g.fillStyle='#18574D';g.font='bold 26px '+FONT;g.fillText(EXCHANGE_TITLE+' — تابع',R,75);}
 let y=top(index);for(const b of items){if(b.cells){let x=R;for(let i=0;i<b.cells.length;i++){const width=b.widths[i];x-=width;g.strokeStyle='#555';g.lineWidth=1;g.strokeRect(x,y,width,b.height);g.font=(b.bold.includes(i)?'bold ':'')+SIZE+'px '+FONT;g.fillStyle=b.bold.includes(i)?'#18574D':'#000000';b.cells[i].forEach((line,j)=>{if(['✓','□'].includes(line)){const cx=x+width/2,cy=y+b.height/2;g.strokeStyle='#000000';g.lineWidth=1.5;g.strokeRect(cx-10,cy-10,20,20);if(line==='✓'){g.beginPath();g.moveTo(cx-7,cy);g.lineTo(cx-1,cy+6);g.lineTo(cx+8,cy-7);g.lineWidth=2.5;g.stroke();}}else g.fillText(line,x+width-10,y+SIZE+7+j*LH);});}}if(b.signature)drawSignatures(g,d,W,M,y+10,SIZE,FONT,true);if(b.image){const im=b.image,ratio=Math.min(WIDTH/im.width,480/im.height);g.drawImage(im,M+(WIDTH-im.width*ratio)/2,y,im.width*ratio,im.height*ratio);g.fillStyle='#000';g.font=SIZE+'px '+FONT;g.fillText(b.label,R,y+510);}y+=b.height;}
 g.font='20px '+FONT;g.fillStyle='#000000';g.fillText('بوابة أم كلثوم الذكية · رقم التوثيق '+record.id,R,1680);g.textAlign='left';g.fillText('صفحة '+(index+1)+' من '+groups.length,M,1680);return canvas;});
}
