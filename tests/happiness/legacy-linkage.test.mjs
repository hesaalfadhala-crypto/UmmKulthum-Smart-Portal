import test from 'node:test';import assert from 'node:assert/strict';
globalThis.window={supabase:{createClient:()=>({})}};
const {normalize}=await import('../../assets/js/portal-data.js');
const {isHappiness,happinessStats}=await import('../../assets/js/happiness-model.js');
const {archiveEntries,filterEntries}=await import('../../assets/js/smart-archive.js');
test('canonical links include old rows; activity-only future rows work without a tag; no source mutation',()=>{
 const rows=[{id:1,_happiness:true,created_by:'a',activity_type:'فعالية',details:{committees:[],goal:'الهدف الأصلي'}},{id:2,activity_type:'لجنة السعادة',details:{happiness:{schemaVersion:1,activity:'ترنداتي'}}},{id:3,activity_type:'فعالية',details:{projects:['لجنة السعادة']}},{id:4,activity_type:'فعالية',details:{committees:['لجنة اليونسكو']}}];
 const original=JSON.stringify(rows);const entries=archiveEntries(rows,{periods:[],plans:[],publications:[]},[]);const tags=[{id:20,kind:'committee',name:'لجنة السعادة'}];const result=filterEntries(entries,{committee:'20'},[],tags);assert.deepEqual(result.map(e=>e.row.id).sort(),[1,2,3]);assert.deepEqual(rows.filter(r=>isHappiness(normalize(r).data)).map(r=>r.id),[1,2,3]);assert.equal(JSON.stringify(rows),original);assert.equal(result.find(e=>e.row.id===1).happinessProject,'غير محدد في التقرير السابق');assert.equal(happinessStats(result.map(e=>({...e.row,data:e.data}))).old,2);
});
