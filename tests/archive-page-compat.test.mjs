import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {JSDOM} from 'jsdom';
import {buildingArchiveVisible,healthCommitteeId,BD_PROJECT_FILTER} from '../assets/js/building-documentation-model.js';
import {TEACHING_AREA,TEACHING_CONTENTS,TEACHING_CONTENTS_LABEL,teachingContentIds,teachingContentLabels} from '../assets/js/teaching-contents.js';
const source=readFileSync(new URL('../assets/js/smart-archive.js',import.meta.url),'utf8');
for(const page of ['archive.html','smart-archive.html'])for(const legacy of [false,true])test(`${page}: load and filter reports${legacy?' without statistics container':''}`,()=>{
 const dom=new JSDOM(readFileSync(new URL('../'+page,import.meta.url),'utf8'));
 const {document}=dom.window;
 if(legacy)document.getElementById('motivationStats').remove();
 const script=source.replace(/^import .*;\n/gm,'').replace(/export /g,'').split("if(typeof document!==")[0];
 const element=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const context=vm.createContext({document,element,TEACHING_AREA,TEACHING_CONTENTS_LABEL,teachingContentIds,teachingContentLabels,renderHappinessStats(){},buildingArchiveVisible,healthCommitteeId,BD_PROJECT_FILTER,motivationStats:()=>({reports:1,beneficiaries:3,missing:0,departments:[],dates:[],years:[]}),normalize:r=>({data:r.details}),console});
 vm.runInContext(script+`;entries=[{kind:'documentation',title:'تقرير تجريبي',areas:[TEACHING_AREA],data:{areas:[TEACHING_AREA],teachingContents:['5','8']},department:'العلوم',date:'2026-10-17',row:{id:99,details:{}},href:'report.html?id=99'}];render();`,context);
 assert.equal(document.querySelectorAll('#results article').length,1);
 assert.match(document.getElementById('motivationStats').textContent,/عدد التقارير: 1/);
 document.getElementById('search').value='غير موجود';vm.runInContext('render()',context);
 assert.equal(document.querySelectorAll('#results article').length,0);
 document.getElementById('search').value='';vm.runInContext('render()',context);
 assert.equal(document.querySelectorAll('#results article').length,1);
 assert.equal(document.querySelectorAll('#motivationStats').length,1);
 const filter=document.getElementById('teachingContent');
 for(const item of TEACHING_CONTENTS)filter.add(new dom.window.Option(item.label,item.id));
 assert.equal(document.getElementById('teachingContentFilter').hidden,true);
 document.getElementById('area').value=TEACHING_AREA;
 for(const id of ['5','8','2']){
  filter.value=id;vm.runInContext('render()',context);
  assert.equal(document.getElementById('teachingContentFilter').hidden,false);
  assert.deepEqual([...document.querySelectorAll('#results a')].map(a=>a.getAttribute('href')),id==='2'?[]:['report.html?id=99']);
 }
 document.getElementById('area').value='';vm.runInContext('render()',context);
 assert.equal(filter.value,'');
 assert.equal(document.getElementById('statDocs').textContent,'1');
 dom.window.close();
});
