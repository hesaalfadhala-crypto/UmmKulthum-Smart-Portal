import {CRITERIA,EXCHANGE_TITLE,visitRows} from './exchange-visit-model.js';
const el=(tag,text)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;return n;};
export function renderExchange(container,d){container.replaceChildren();container.classList.add('exchange-report');container.append(el('h2',EXCHANGE_TITLE));
 const table=()=>{const t=el('table');t.className='exchange-table';container.append(t);return t;};
 const meta=table();for(const row of visitRows(d)){const tr=el('tr');row.forEach((s,i)=>tr.append(el(i%2?'td':'th',s||'—')));meta.append(tr);}
 const t=table(),head=el('thead'),hr=el('tr');['عناصر الدرس','معايير الملاحظة','✓'].forEach(s=>hr.append(el('th',s)));head.append(hr);t.append(head);const body=el('tbody');t.append(body);
 for(const c of CRITERIA){const tr=el('tr'),domain=el('td',c.domain);domain.className='domain';tr.append(domain,el('td',c.text));const mark=el('td',(d.exchangeVisit?.selected||[]).includes(c.id)?'✓':'□');mark.className='mark';tr.append(mark);body.append(tr);}
 for(const [label,value]of [['أبرز الممارسات المستفادة من الزيارة',d.exchangeVisit?.practices],['المعلمة الزائرة',d.exchangeVisit?.visitorName||d.executor],['المعلمة الأولى أو المنسقة',d.exchangeVisit?.coordinatorName],['متابعة المديرة المساعدة',d.exchangeVisit?.followUp]]){const t=table(),tr=el('tr');tr.append(el('th',label),el('td',value||'—'));t.append(tr);}
}
