import {tabularExcel} from './tabular-excel.js';
import {element} from './portal-data.js?v=20261021-unified';
export function downloadRoster(students,title='المشاركات'){const bytes=tabularExcel([['اسم الطالبة','الصف','الشعبة','المركز المحقق'],...students.map(s=>[s.name,s.class,s.section||'',s.place||''])]);const a=element('a');a.href=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));a.download=title.replace(/[\\/:*?"<>|]/g,'').slice(0,70)+'.xlsx';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),20000);}
