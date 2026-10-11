import {CRITERIA,DOMAINS} from './visit-criteria.js';
export function distribution(values){const counts=[0,0,0,0];for(const v of values)if(Number.isInteger(v)&&v>=1&&v<=4)counts[v-1]++;const n=counts.reduce((a,b)=>a+b,0);return {counts,n,percent:n?counts.map(x=>100*x/n):null};}
export const percent=(v)=>v==null?'لا توجد بيانات':v.toFixed(2)+'%';
export function analyze(snapshot){
 const visits=snapshot.visits||[],ratings=snapshot.ratings||[],details=snapshot.details||[],teachers=snapshot.teachers||[];
 const valid=new Set(visits.filter(v=>v.status==='final').map(v=>v.id));
 const rs=ratings.filter(r=>valid.has(r.visit_id));
 const criteria=CRITERIA.map(c=>({...c,...distribution(rs.filter(r=>r.criterion_id===c.id).map(r=>r.level))}));
 const domains=DOMAINS.map(d=>({...d,...distribution(rs.filter(r=>d.ids.includes(r.criterion_id)).map(r=>r.level))}));
 const judged=details.filter(d=>valid.has(d.visit_id));
 const visited=new Set(visits.filter(v=>v.status==='final').map(v=>v.teacher_id));
 const eligible=new Set(snapshot.coverage_teacher_ids||[]);
 const denominator=snapshot.coverage_known?eligible.size:null;
 const covered=[...visited].filter(id=>eligible.has(id)).length;
 return {criteria,domains,judgment:distribution(judged.map(d=>d.final_judgment)),visitCount:valid.size,teacherCount:visited.size,eligibleTeachers:denominator,coverage:denominator?100*covered/denominator:null,ratings:rs,details:judged,visits:visits.filter(v=>valid.has(v.id)),teachers};
}
export function compare(a,b){return {a,b,criteria:a.criteria.map((c,i)=>{const d=b.criteria[i];const pa=c.n?100*(c.counts[2]+c.counts[3])/c.n:null,pb=d.n?100*(d.counts[2]+d.counts[3])/d.n:null;const change=pa==null||pb==null?null:pb-pa;return {id:c.id,text:c.text,from:pa,to:pb,change,status:change==null?'لا توجد بيانات كافية':change>0?'تحسن في نسبة تجاوز التوقعات':change<0?'يحتاج إلى متابعة':'لم تتغير النسبة',nFrom:c.n,nTo:d.n};})};}
export function reportRows(analysis){return DOMAINS.flatMap(d=>[{kind:'domain',id:'',text:d.name,...analysis.domains.find(x=>x.id===d.id)},...analysis.criteria.filter(c=>d.ids.includes(c.id)).map(c=>({...c,kind:'criterion'}))]);}
