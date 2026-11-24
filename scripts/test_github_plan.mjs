import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
const read = p => readFileSync(new URL('../'+p,import.meta.url),'utf8');
const body=read('frontend/opc/project_plan_github.mbt').split('\n///|')[0].split('\n').filter(l=>/^\s*#\|/.test(l)).map(l=>l.replace(/^\s*#\| ?/,'')).join('\n');
const convert=vm.runInNewContext(`(${body})`);
const issue=(number=7,repo='demo')=>({number,title:'Build a useful thing, 中文',body:'First line\n- [ ] Deliver it',url:`https://github.com/team/${repo}/issues/${number}`,state:'OPEN',assignees:[{login:'lee'}],labels:[{name:'customer'}],milestone:{title:'Launch'}});
function parse(rows){return JSON.parse(convert(JSON.stringify(rows)));}
function success(rows){const r=parse(rows);assert.equal(r.error,'');return JSON.parse(r.template);}
test('open issues become editable template tasks with source context',()=>{
 const t=success([issue(),{...issue(8),state:'CLOSED'}]);assert.equal(t.format,'moonproj-plan-template/v1');assert.equal(t.tasks.length,1);assert.equal(t.tasks[0].name,issue().title);
 assert.deepEqual(t.tasks[0],{id:'gh-github.com-team-demo-7',name:issue().title,owner:'',milestone:'',cost:'',dependencies:[]});
 for(const s of ['First line','Deliver it','https://github.com/team/demo/issues/7','lee','customer','Launch','1 closed issues excluded']) assert.ok(t.notes.includes(s),s);
 assert.equal(t.currency,'');assert.deepEqual(t.milestones,[]);
});
test('same issue number in different repositories stays distinct and deterministic',()=>{
 const rows=[issue(),issue(7,'another')];const t=success(rows);assert.notEqual(t.tasks[0].id,t.tasks[1].id);assert.equal(convert(JSON.stringify(rows)),convert(JSON.stringify(rows)));
});
test('ordinary malformed or unusable input reports an error without a partial template',()=>{
 for(const rows of [[],[{...issue(),state:'CLOSED'}],[issue(),issue()],[{...issue(),url:'https://github.com/team/demo/issues/9'}],[{...issue(),state:'done'}]]) {const r=parse(rows);assert.ok(r.error);assert.equal(r.template,'');}
 assert.ok(JSON.parse(convert('{')).error);
});
test('existing preview replacement and append paths retain GitHub source notes',()=>{
 const ui=read('frontend/opc/project_plan_template.mbt');assert.match(ui,/PreviewGithub/);assert.match(ui,/plan_github_read_template\(t.source\)/);assert.match(ui,/trello: action == PreviewTrello \|\| action == PreviewGithub/);assert.match(ui,/notes: d.notes \+ "\\n\\n" \+ preview.notes/);assert.match(ui,/Template\(PreviewGithub\)/);
});
