import {client,requireUser} from './portal-data.js?v=20261021-unified';
async function refresh(){const root=document.getElementById('hasadHomeBell');if(!root)return;try{const user=await requireUser();const {data,error}=await client.from('hasad_notifications').select('id').eq('recipient_id',user.id).is('read_at',null);if(error)throw error;root.textContent=data.length?'🔔 '+data.length:'';root.setAttribute('aria-label',data.length+' إشعارات تكريم غير مقروءة');}catch{root.textContent='';}}
void refresh();window.addEventListener('focus',()=>void refresh());
