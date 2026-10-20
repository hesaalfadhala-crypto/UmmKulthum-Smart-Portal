import {fetchRecords,normalize,element} from './portal-data.js?v=20261021-unified';
const cards=[...document.querySelectorAll('.project')],search=document.querySelector('.search');
search.addEventListener('input',()=>cards.forEach(card=>card.hidden=!card.querySelector('h3').textContent.toLowerCase().includes(search.value.trim().toLowerCase())));
async function load(){try{
 const rows=await fetchRecords();let linked=0;
 document.querySelector('.summary .stat:first-child strong').textContent=cards.length;
 for(const card of cards){
  const name=card.querySelector('h3').textContent.trim(),matching=rows.filter(row=>normalize(row).data.projects.includes(name));
  card.querySelector('.project-footer span:last-child').textContent=matching.length;
  card.querySelector('.status').textContent=matching.length?'توثيقات محفوظة':'لا توجد توثيقات';
  if(matching.length){const list=element('div');for(const row of matching){const link=element('a',normalize(row).data.activity);link.href='report.html?id='+encodeURIComponent(String(row.id));link.style.display='block';list.append(link);}card.append(list);}
 }
 linked=rows.filter(row=>normalize(row).data.projects.some(name=>cards.some(c=>c.querySelector('h3').textContent.trim()===name))).length;
 document.querySelector('.summary .stat:nth-child(2) strong').textContent=linked;
}catch(error){document.querySelector('.heading').append(element('p',error.message));}}
void load();
