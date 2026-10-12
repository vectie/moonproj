import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open,openHTML,source,returnedReview} from './helpers/plan_review_harness.mjs';
const walk=e=>[e,...e.children.flatMap(walk)];
const find=(app,id)=>[...walk(app.ids.review),...walk(app.ids['revision-previous'])].find(e=>e.id===id);
const text=e=>walk(e).map(v=>v.textContent).join('\n');
const history=app=>text(app.ids.review);
async function load(app,packet,id='revision-load') {
  app.ids[id].files=[new Blob([typeof packet==='string'?packet:JSON.stringify(packet)])];await app.ids[id].fire('change');
}
async function pair(app,current,previous) { const c=find(app,'revision-pair-'+current);c.value=String(previous);await c.fire('change'); }
async function save(app) {const n=app.downloads.length;await app.ids['revision-save'].fire('click');return n===app.downloads.length ? undefined : JSON.parse(await app.downloads.at(-1).text());}
function revisedSource() {
  const value=JSON.parse(source), previous=value.tasks;
  value.notes+='\nRevision: add a kickoff and remove delivery preparation.';
  value.tasks=[{id:'task-1',name:'Kickoff interview',owner:'owner-2',milestone:'milestone-1',cost:'20.00',dependencies:[]},
    {...previous[0],id:'task-2',dependencies:['task-1']},
    {...previous[1],id:'task-3',name:'Draft source-backed brief',dependencies:['task-2']},
    {...previous[2],id:'task-4',dependencies:['task-3']}];
  value.risks[0].tasks=['task-2','task-3'];
  return JSON.stringify(value);
}
async function fixture() {
  const prior=await returnedReview('Sam',{3:{state:'change-requested',note:'Need a wider source set.'},6:{state:'question',note:'Who sends the final copy?'}});
  const app=open(revisedSource());await load(app,prior);return {app,prior};
}

test('new revision loads historical feedback without copying any current decision or matching reused positional slots',async()=>{
  const {app,prior}=await fixture();const packet=await save(app);
  assert.equal(packet.schema,'moonproj.plan-review-revision.v1');assert.equal(packet.previous_review.source_template,source);
  assert.deepEqual(packet.previous_review,prior);assert.equal(packet.source_template,revisedSource());
  assert.deepEqual(packet.pairing,[0,...new Array(9).fill(null)]);
  assert.ok(app.states.every(s=>s.value==='not-reviewed'));assert.ok(app.notes.every(n=>n.value===''));
  assert.equal(app.ids.reviewer.value,'');assert.match(app.ids['revision-summary'].textContent,/0 paired rows/);
  assert.match(history(app),/UNRESOLVED current row/);assert.doesNotMatch(history(app),/Historical reviewer note:\nNeed a wider source set/);
});

test('explicit shifted row pairing shows old feedback, full changed fields, position and linked context',async()=>{
  const {app}=await fixture();await pair(app,4,3);
  const body=history(app);assert.match(body,/Historical reviewer note:\nNeed a wider source set/);
  assert.match(body,/Historical state: change-requested; never a decision on this current plan/);
  assert.match(body,/Literal fields differ: id, dependencies/);assert.match(body,/position 1 → current position 2 \(POSITION CHANGED\)/);
  assert.match(body,/PREVIOUS linked context/);assert.match(body,/CURRENT linked context/);assert.match(body,/Kickoff interview/);
  assert.equal(app.states[4].value,'not-reviewed');assert.equal(app.notes[4].value,'');
  const packet=await save(app);assert.equal(packet.pairing[3],null);assert.equal(packet.pairing[4],3);
});

test('added and removed labels preserve full historical rows and cannot masquerade as current review',async()=>{
  const {app}=await fixture();await pair(app,3,'added');await find(app,'revision-remove-6').fire('click');
  const packet=await save(app);assert.equal(packet.pairing[3],'added');assert.deepEqual(packet.removed,[6]);
  assert.match(history(app),/Marked ADDED by reviewer/);
  assert.match(text(app.ids['revision-previous']),/REMOVED \(reviewer assertion\): tasks: Prepare delivery/);
  assert.match(text(app.ids['revision-previous']),/Who sends the final copy/);
  assert.equal(JSON.parse(packet.previous_review.source_template).tasks.length,4);assert.equal(JSON.parse(packet.source_template).tasks.length,4);
  await find(app,'revision-remove-6').fire('click');assert.deepEqual((await save(app)).removed,[]);
});

test('file journey: compare revised plan, save pairings and new notes, reopen both, return review to its current inbox',async()=>{
  const {app,prior}=await fixture();await pair(app,3,'added');await pair(app,4,3);await pair(app,5,4);await pair(app,6,5);await find(app,'revision-remove-6').fire('click');
  const comparison=await save(app);app.ids.reviewer.value='Sam';app.states[4].value='no-change-requested';app.notes[4].value='New source requirement is clear.';await app.ids.review.fire('input');
  const current=await app.save(),dir=mkdtempSync(join(tmpdir(),'moonproj-revision-'));
  try {
    writeFileSync(join(dir,'current.html'),app.html);writeFileSync(join(dir,'comparison.json'),JSON.stringify(comparison));writeFileSync(join(dir,'current-notes.json'),JSON.stringify(current));
    const resumed=openHTML(readFileSync(join(dir,'current.html'),'utf8'));await load(resumed,readFileSync(join(dir,'comparison.json'),'utf8'),'revision-resume');
    await resumed.load(readFileSync(join(dir,'current-notes.json'),'utf8'));
    assert.deepEqual(await save(resumed),comparison);assert.deepEqual(await resumed.save(),current);assert.match(history(resumed),/Need a wider source set/);
    const preparer=open(revisedSource());await preparer.importReviews(current);assert.deepEqual((await preparer.saveInbox()).reviews[0].review,current);
    await preparer.importReviews(prior);assert.match(preparer.ids['inbox-status'].textContent,/different exact plan snapshot/);
    assert.equal((await preparer.saveInbox()).reviews.length,1);
  } finally {rmSync(dir,{recursive:true,force:true});}
});

test('one-to-one pairing and removal require explicit undo without disturbing existing mappings or decisions',async()=>{
  const {app}=await fixture();app.notes[0].value='Current scope note';await app.ids.review.fire('input');await pair(app,4,3);const before=await save(app);
  await pair(app,5,3);assert.match(app.ids['revision-status'].textContent,/repeated previous row/);assert.deepEqual(await save(app),before);
  await find(app,'revision-remove-6').fire('click');await pair(app,5,6);assert.match(app.ids['revision-status'].textContent,/Removed rows/);
  assert.equal(app.notes[0].value,'Current scope note');assert.equal((await save(app)).pairing[5],null);
  await pair(app,4,'');await pair(app,5,3);assert.equal((await save(app)).pairing[5],3);
});

test('equal row fields still show changed linked owner context without asserting unchanged review validity',async()=>{
  const prior=await returnedReview('Sam',{3:{state:'no-change-requested',note:'Owner has relevant experience.'}}),value=JSON.parse(source);value.owners[0].name='New owner';
  const app=open(JSON.stringify(value));await load(app,prior);await pair(app,3,3);
  assert.match(history(app),/No literal row-field differences. This does not establish unchanged meaning or review validity/);
  assert.match(history(app),/"name": "Alex"/);assert.match(history(app),/"name": "New owner"/);assert.equal(app.states[3].value,'not-reviewed');
});

test('cancelled replace or clear keeps pairing work, and successful clear leaves current notes and inbox intact',async()=>{
  const {app,prior}=await fixture();await pair(app,4,3);app.notes[0].value='Keep current notes';await app.ids.review.fire('input');const own=await app.save();await app.importReviews(own);
  const before=await save(app),inbox=await app.saveInbox();app.window.confirm=()=>false;await load(app,prior);await app.ids['revision-clear'].fire('click');assert.deepEqual(await save(app),before);
  app.window.confirm=()=>true;await app.ids['revision-clear'].fire('click');assert.equal(await save(app),undefined);
  assert.equal(app.notes[0].value,'Keep current notes');assert.deepEqual(await app.saveInbox(),inbox);assert.doesNotMatch(history(app),/Historical reviewer note/);
});

test('comparison restore validates both snapshot associations and previous source shape before replacement',async()=>{
  const {app}=await fixture();await pair(app,4,3);const before=await save(app),bad=structuredClone(before);bad.source_template+=' ';
  await load(app,bad,'revision-resume');assert.match(app.ids['revision-status'].textContent,/different exact current plan snapshot/);assert.deepEqual(await save(app),before);
  const missing=structuredClone(before);missing.previous_review.annotations.pop();await load(app,missing,'revision-resume');assert.match(app.ids['revision-status'].textContent,/incomplete/);assert.deepEqual(await save(app),before);
  const unsupported=structuredClone(before.previous_review);const plan=JSON.parse(unsupported.source_template);plan.tasks[0].approved=true;unsupported.source_template=JSON.stringify(plan);
  await load(app,unsupported);assert.match(app.ids['revision-status'].textContent,/Unsupported previous tasks row/);assert.deepEqual(await save(app),before);
});

test('slow comparison reads cannot overwrite newer pairing edits, a cleared reference, or a newer file',async()=>{
  const {app,prior}=await fixture();let resolve;
  app.ids['revision-load'].files=[{size:100,text:()=>new Promise(r=>resolve=r)}];const pending=app.ids['revision-load'].fire('change');await pair(app,4,3);resolve(JSON.stringify(prior));await pending;assert.equal((await save(app)).pairing[4],3);
  app.ids['revision-load'].files=[{size:100,text:()=>new Promise(r=>resolve=r)}];const cleared=app.ids['revision-load'].fire('change');await app.ids['revision-clear'].fire('click');resolve(JSON.stringify(prior));await cleared;assert.equal(await save(app),undefined);
  app.ids['revision-load'].files=[{size:100,text:()=>new Promise(r=>resolve=r)}];const stale=app.ids['revision-load'].fire('change');await load(app,{...prior,reviewer:'Newer'});resolve(JSON.stringify(prior));await stale;assert.match(app.ids['revision-summary'].textContent,/Historical reviewer: Newer/);
});

test('save warns about both plans and separate current notes; unconfirmed pairing download retains close warning',async()=>{
  const {app}=await fixture();let warned=false;const event={preventDefault:()=>warned=true};await app.window.fire('beforeunload',event);assert.equal(warned,false);
  await pair(app,4,3);await save(app);assert.match(app.ids['revision-status'].textContent,/both full plans/);assert.match(app.ids['revision-status'].textContent,/Save current review notes separately/);
  await app.window.fire('beforeunload',event);assert.equal(warned,true);await app.ids['revision-clear'].fire('click');warned=false;await app.window.fire('beforeunload',event);assert.equal(warned,false);
});
