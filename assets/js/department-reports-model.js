export function departmentReports(rows,department,filters={}){
 const q=String(filters.query||'').trim().toLocaleLowerCase();
 return [...new Map(rows.filter(r=>!r.deleted_at&&(r.department===department||r.activity_type==='اجتماع'&&String(r.department||'').split(' • ').includes(department))&&r.status==='published').map(r=>[String(r.id),r])).values()].filter(r=>(!filters.kind||r.activity_type===filters.kind)&&(!filters.from||(r.activity_date||String(r.created_at).slice(0,10))>=filters.from)&&(!filters.to||(r.activity_date||String(r.created_at).slice(0,10))<=filters.to)&&(!filters.year||(r.academic_year||r.details?.academicYear||'')===filters.year)&&(!q||[r.activity,r.activity_type,r.executor,filters.names?.get(r.created_by)].join(' ').toLocaleLowerCase().includes(q))).sort((a,b)=>String(b.activity_date||b.created_at).localeCompare(String(a.activity_date||a.created_at)));
}
export function teacherGroups(staff,records,department){
 const people=new Map(staff.filter(p=>p.departments?.includes(department)||records.some(r=>r.created_by===p.id)).map(p=>[p.id,p]));
 for(const r of records)if(!people.has(r.created_by))people.set(r.created_by,{id:r.created_by,name:'مستخدمة غير متاحة في دليل القسم',job_title:''});
 return [...people.values()].map(p=>({...p,reports:records.filter(r=>r.created_by===p.id)})).sort((a,b)=>a.name.localeCompare(b.name,'ar'));
}
