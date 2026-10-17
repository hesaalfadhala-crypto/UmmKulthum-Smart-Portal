// The standalone competition form stores the specified text in its existing columns.
const fields=new Map();
for(const key of ['department','competitionLevel','result']){
 const source=key==='result'?document.querySelector('.radio-group'):document.getElementById(key);
 const wrap=document.createElement('div');wrap.className='field';const label=document.createElement('label'),input=document.createElement('input');input.id=key+'Other';input.maxLength=300;label.htmlFor=input.id;label.textContent='يرجى التحديد';input.setAttribute('aria-label','يرجى التحديد — '+({department:'القسم',competitionLevel:'مستوى المسابقة',result:'النتيجة'}[key]));wrap.append(label,input);source.after(wrap);
 const value=()=>key==='result'?document.querySelector('[name=result]:checked')?.value||'':source.value;
 const active=()=>!(key==='competitionLevel'&&document.getElementById('competitionType').value!=='خارجية');
 const update=()=>{wrap.hidden=!active()||value()!=='أخرى';input.required=!wrap.hidden;};source.addEventListener('change',update);document.getElementById('competitionType').addEventListener('change',update);fields.set(key,{input,value,active,update});update();
}
window.competitionOther=()=>Object.fromEntries([...fields].map(([key,f])=>{f.update();const v=f.value();if(f.active()&&v==='أخرى'&&(!f.input.value.trim()||f.input.value.trim().length>300))throw new Error('يرجى التحديد: '+({department:'القسم',competitionLevel:'مستوى المسابقة',result:'النتيجة'}[key]));return [key,v==='أخرى'&&f.active()?f.input.value.trim():v];}));
