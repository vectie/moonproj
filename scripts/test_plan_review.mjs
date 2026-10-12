import test from 'node:test';
import assert from 'node:assert/strict';
import {open, source, read} from './helpers/plan_review_harness.mjs';
test('production HTML renderer opens every source row with exact full details',()=>{
  const app=open(),plan=JSON.parse(source);
  assert.equal(app.states.length,1+['owners','tasks','milestones','risks'].reduce((n,k)=>n+plan[k].length,0));
  assert.ok(app.states.every(e=>e.value==='not-reviewed'));
  const pre=app.created.filter(e=>e.tag==='pre');
  assert.deepEqual(JSON.parse(pre[1].textContent),plan.owners[0]);
  assert.ok(pre.some(e=>JSON.parse(e.textContent).evidence === plan.milestones[0].evidence));
  assert.match(app.html,/Nothing is sent automatically/);
});
test('annotate, actual Blob download, reopen original sheet and restore exact feedback',async()=>{
  const a=open(); a.ids.reviewer.value='李 / Sam';a.states[2].value='question';a.notes[2].value='What evidence?\n保留原文';
  await a.ids.review.fire('input');const saved=await a.save();
  assert.equal(saved.source_template,source);assert.equal(saved.annotations[2].note,a.notes[2].value);
  assert.equal(saved.schema,'moonproj.plan-review-notes.v1');assert.equal(a.created.find(e=>e.tag==='a').download,'plan-review-notes.json');
  assert.deepEqual(a.revoked,['blob:review']);
  const b=open();await b.load(saved);assert.equal(b.notes[2].value,a.notes[2].value);assert.equal(b.states[2].value,'question');assert.equal(b.ids.reviewer.value,'李 / Sam');
  assert.deepEqual(await b.save(),saved);
});
test('exact source bytes bind reviews even when whitespace-only snapshot changes',async()=>{
  const a=open();const saved=await a.save();const b=open(source+'\n');b.notes[0].value='Keep';await b.load(saved);
  assert.equal(b.notes[0].value,'Keep');assert.match(b.ids.status.textContent,/different exact plan snapshot/);
});
test('full template and hostile text are displayed only as text, not executable HTML',async()=>{
  const p=JSON.parse(source);p.notes='</script><img src=x onerror=alert(1)> & 中文\u2028';p.tasks[0].name='<script>evil()</script>';
  const a=open(JSON.stringify(p));assert.equal((a.html.match(/<script>/g)||[]).length,1);assert.equal((a.html.match(/<\/script>/g)||[]).length,1);
  assert.ok(a.created.some(e=>e.tag==='pre'&&e.textContent.includes('</script>')));
  assert.equal((await a.save()).source_template,JSON.stringify(p));assert.match(a.html,/connect-src 'none'/);
});
test('unreadable, invalid or incomplete review preserves all existing edits atomically',async()=>{
  const a=open(),packet=await a.save();a.notes[0].value='Local';a.ids.reviewer.value='Local reviewer';
  for(const bad of ['{', {...packet,annotations:packet.annotations.slice(1)}, {...packet,extra:true}, {...packet,annotations:packet.annotations.map((r,i)=>i===2?{...r,state:'approved'}:r)}]){
    await a.load(bad);assert.equal(a.notes[0].value,'Local');assert.equal(a.ids.reviewer.value,'Local reviewer');
  }
  a.ids.load.files=[{size:10,text:async()=>{throw Error('Cannot read file');}}];await a.ids.load.fire('change');assert.match(a.ids.status.textContent,/Cannot read/);
});
test('reviewer, note and size bounds have repairable failures',async()=>{
  const a=open();a.ids.reviewer.value='x'.repeat(1001);await a.ids.save.fire('click');assert.equal(a.downloads.length,0);
  a.ids.reviewer.value='';a.notes[0].value='x'.repeat(16385);await a.ids.save.fire('click');assert.equal(a.downloads.length,0);
  a.ids.load.files=[{size:40000001,text:()=>{throw Error('must not read');}}];await a.ids.load.fire('change');assert.match(a.ids.status.textContent,/40 MB/);
});
test('dirty review import requires explicit replace and cancellation preserves edits',async()=>{
  const a=open(),saved=await a.save();a.notes[0].value='Unsaved';await a.ids.review.fire('input');a.window.confirm=()=>false;
  await a.load(saved);assert.equal(a.notes[0].value,'Unsaved');a.window.confirm=()=>true;await a.load(saved);assert.equal(a.notes[0].value,'');
});
test('editing or selecting a newer file while read is pending prevents stale overwrite',async()=>{
  const a=open(),saved=await a.save();let release;const deferred=new Promise(r=>release=r);
  a.ids.load.files=[{size:100,text:()=>deferred}];const pending=a.ids.load.fire('change');
  a.notes[0].value='Newer edit';await a.ids.review.fire('input');release(JSON.stringify(saved));await pending;assert.equal(a.notes[0].value,'Newer edit');
  let release2;const deferred2=new Promise(r=>release2=r);a.ids.load.files=[{size:100,text:()=>deferred2}];const pending2=a.ids.load.fire('change');
  saved.annotations[0].note='Newer file';await a.load(saved);release2(JSON.stringify({...saved,reviewer:'Old file'}));await pending2;assert.equal(a.notes[0].value,'Newer file');assert.equal(a.ids.reviewer.value,'');
});
test('close warning covers edits even after unconfirmed download and restores cleanly',async()=>{
  const a=open();let warned=false;const event={preventDefault:()=>warned=true};await a.window.fire('beforeunload',event);assert.equal(warned,false);
  await a.ids.review.fire('input');const saved=await a.save();await a.window.fire('beforeunload',event);assert.equal(warned,true);
  await a.load(saved);warned=false;await a.window.fire('beforeunload',event);assert.equal(warned,false);
});
test('unchanged source and blank unknown costs or dates are never inferred',async()=>{
  const p=JSON.parse(source);p.tasks[0].cost='';p.milestones[0].date='unplanned';const bytes=JSON.stringify(p);const a=open(bytes),saved=await a.save();
  assert.equal(saved.source_template,bytes);assert.equal(JSON.parse(saved.source_template).tasks[0].cost,'');assert.ok(saved.annotations.every(r=>r.state==='not-reviewed'));
});
test('source-only integration uses current draft existing export codec, separate download and no mutation',()=>{
  const ui=read('frontend/opc/project_plan_template.mbt');assert.match(ui,/Template\(DownloadReview\)/);assert.match(ui,/Download \| DownloadReview =>/);
  const section=ui.split('    Download | DownloadReview => {')[1].split('    Apply =>')[0];
  assert.match(section,/@plan_workbench\.export_template\(d\)/);assert.match(section,/plan_download\(plan_review_html\(exported\), "plan-review.html", false\)/);assert.match(section,/\n        model,/);assert.doesNotMatch(section,/plan_save_edit|fetch|localStorage/);
});
