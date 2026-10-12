import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open,openHTML,source,returnedReview} from './helpers/plan_review_harness.mjs';
const feedback = note => ({state:'question',note});
const edit = async (app,index,row,disposition,response) => {
  const id=`response-${index}-${row}`;
  const state=app.control(id),note=app.control(id+'-text');
  state.value=disposition;await state.fire('change');note.value=response;await note.fire('input');
};
const visibleResponses = app => app.inboxElements().filter(e=>e.tag==='select');

test('collect reviewers, group exact task context, keep conflicting observations and coverage',async()=>{
  const first=await returnedReview('Sam',{3:feedback('Which three examples?'),4:{state:'no-change-requested',note:'Keep the citations.'}});
  const second=await returnedReview('李',{3:{state:'change-requested',note:'Use four examples instead.'}});
  const app=open();await app.importReviews(first,second);
  assert.equal(visibleResponses(app).length,3);
  assert.equal(app.inboxElements().filter(e=>e.tag==='h3').length,2);
  const task=JSON.parse(source).tasks[0];
  assert.ok(app.inboxElements().some(e=>e.tag==='pre' && e.textContent===JSON.stringify(task,null,2)));
  assert.ok(app.inboxElements().some(e=>e.textContent==='Which three examples?'));
  assert.ok(app.inboxElements().some(e=>e.textContent==='Use four examples instead.'));
  assert.match(app.ids['inbox-summary'].textContent,/2 review files; 3 feedback items; 3 need action/);
  assert.ok(app.inboxElements().some(e=>e.tag==='p'&&e.textContent.includes('not-reviewed')));
  assert.ok(app.states.every(e=>e.value==='not-reviewed'));
  assert.deepEqual((await app.saveInbox()).reviews.map(item=>item.review),[first,second]);
});

test('preparer can answer, plan changes, explain non-adoption and focus remaining action',async()=>{
  const app=open();await app.importReviews(await returnedReview('Sam',{3:feedback('A?'),4:feedback('B?'),5:feedback('C?')}));
  await edit(app,0,3,'answered','See source note 3.');
  await edit(app,0,4,'change-planned','Revise the criterion in the next snapshot.');
  await edit(app,0,5,'not-adopted','Outside this bounded scope.');
  await app.filter('needs-action');
  assert.deepEqual(visibleResponses(app).map(e=>e.id),['response-0-4']);
  assert.match(app.ids['inbox-summary'].textContent,/1 need action/);
  await edit(app,0,4,'answered','New clarification supplied, review still pending.');
  assert.equal(visibleResponses(app).length,1,'editing does not remove the focused control');
  await app.ids['inbox-refresh'].fire('click');assert.equal(visibleResponses(app).length,0);
  await app.filter('all');assert.equal(visibleResponses(app).length,3);
  const saved=await app.saveInbox();assert.equal(saved.reviews[0].review.annotations[4].note,'B?');
  assert.equal(saved.responses[1].response,'New clarification supplied, review still pending.');
  assert.match(app.ids['inbox-summary'].textContent,/not reviewer agreement or approval/);
});

test('download actual inbox Blob, save to disk, reopen and restore exact source, reviews and responses',async()=>{
  const app=open();const review=await returnedReview('李 / Sam',{3:feedback('Which evidence? 🌓')});
  await app.importReviews(review);app.ids.preparer.value='Alex';await app.ids.preparer.fire('input');
  await edit(app,0,3,'change-planned','Add the source reference\n保留原文');
  const saved=await app.saveInbox(),dir=mkdtempSync(join(tmpdir(),'moonproj-inbox-'));
  try {
    writeFileSync(join(dir,'plan-review.html'),app.html);
    writeFileSync(join(dir,'plan-review-inbox.json'),await app.downloads.at(-1).text());
    assert.equal(readFileSync(join(dir,'plan-review.html'),'utf8'),app.html);
    const reopened=openHTML(readFileSync(join(dir,'plan-review.html'),'utf8'));await reopened.loadInbox(readFileSync(join(dir,'plan-review-inbox.json'),'utf8'));
    assert.deepEqual(await reopened.saveInbox(),saved);
    assert.equal(reopened.control('response-0-3-text').value,'Add the source reference\n保留原文');
    assert.equal(reopened.ids.preparer.value,'Alex');
    assert.equal(saved.source_template,source);assert.deepEqual(saved.reviews[0].review,review);
    assert.equal(app.created.filter(e=>e.tag==='a').at(-1).download,'plan-review-inbox.json');
  } finally {rmSync(dir,{recursive:true,force:true});}
});

test('identical returned files are skipped while revised feedback from the same label stays separate',async()=>{
  const review=await returnedReview('Sam',{3:feedback('First question')});const app=open();await app.importReviews(review);
  await edit(app,0,3,'answered','First answer');
  await app.importReviews(JSON.stringify(review,null,2));
  let saved=await app.saveInbox();assert.equal(saved.reviews.length,1);assert.equal(saved.responses[0].response,'First answer');
  const revised=structuredClone(review);revised.annotations[3].note='Revised question';await app.importReviews(revised);
  saved=await app.saveInbox();assert.equal(saved.reviews.length,2);assert.equal(saved.responses[1].disposition,'open');
  assert.equal(saved.responses[0].response,'First answer');
  assert.deepEqual(saved.reviews.map(r=>r.review.reviewer),['Sam','Sam']);
});

test('empty and no-change feedback retain review coverage without claiming approval',async()=>{
  const review=await returnedReview('Sam');for(const row of review.annotations) row.state='no-change-requested';
  const app=open();await app.importReviews(review);
  assert.equal(visibleResponses(app).length,0);const saved=await app.saveInbox();
  assert.equal(saved.reviews[0].review.annotations.length,10);assert.equal(saved.responses.length,0);
  assert.ok(app.inboxElements().some(e=>e.textContent.includes('this is not approval')));
});

test('missing explanations remain actionable and block saving completed dispositions',async()=>{
  const app=open();await app.importReviews(await returnedReview('Sam',{3:feedback('Question')}));
  await edit(app,0,3,'answered','  ');
  assert.match(app.ids['inbox-summary'].textContent,/1 need action/);assert.equal(await app.saveInbox(),undefined);
  assert.match(app.ids['inbox-status'].textContent,/Add a preparer explanation/);
  await app.importReviews(await returnedReview('Other',{4:feedback('Another question')}));
  assert.equal(app.control('response-0-3').value,'answered','import keeps incomplete local edits');
  await edit(app,0,3,'open','');assert.ok(await app.saveInbox());
});

test('different exact snapshot in a batch rejects the whole batch and preserves original responses',async()=>{
  const good=await returnedReview('Sam',{3:feedback('Original')});const app=open();await app.importReviews(good);
  await edit(app,0,3,'answered','Preserve this');const before=await app.saveInbox();
  const bad=structuredClone(good);bad.source_template+='\n';
  await app.importReviews(await returnedReview('New',{4:feedback('New')}),bad);
  assert.match(app.ids['inbox-status'].textContent,/different exact plan snapshot/);
  assert.deepEqual(await app.saveInbox(),before);
  const wrong=open(source+'\n');await wrong.loadInbox(before);
  assert.match(wrong.ids['inbox-status'].textContent,/different exact plan snapshot/);
  assert.equal((await wrong.saveInbox()).reviews.length,0);
});

test('saved inbox validates response association before replacing a dirty session and cancellation retains it',async()=>{
  const app=open();await app.importReviews(await returnedReview('Sam',{3:feedback('A?'),4:feedback('B?')}));
  const original=await app.saveInbox();await edit(app,0,3,'answered','Local answer');
  const invalid=structuredClone(original);invalid.responses.reverse();await app.loadInbox(invalid);
  assert.match(app.ids['inbox-status'].textContent,/Invalid preparer response/);
  assert.equal(app.control('response-0-3-text').value,'Local answer');
  app.window.confirm=()=>false;await app.loadInbox(original);assert.equal(app.control('response-0-3-text').value,'Local answer');
  app.window.confirm=()=>true;await app.loadInbox(original);assert.equal(app.control('response-0-3-text').value,'');
});

test('pending imports cannot overwrite newer edits or a newer loaded inbox',async()=>{
  const review=await returnedReview('Sam',{3:feedback('Question')});const app=open();await app.importReviews(review);
  const saved=await app.saveInbox();let release;
  app.ids['inbox-load'].files=[{size:100,text:()=>new Promise(r=>release=r)}];const pending=app.ids['inbox-load'].fire('change');
  await edit(app,0,3,'answered','New edit');release(JSON.stringify(saved));await pending;
  assert.equal(app.control('response-0-3-text').value,'New edit');
  let releaseImport;app.ids['inbox-import'].files=[{size:100,name:'later.json',text:()=>new Promise(r=>releaseImport=r)}];
  const pendingImport=app.ids['inbox-import'].fire('change');await app.loadInbox(saved);
  const other=structuredClone(review);other.reviewer='Other';releaseImport(JSON.stringify(other));await pendingImport;
  assert.equal((await app.saveInbox()).reviews.length,1);
});

test('inbox close warning is independent of reviewer draft restore and clear requires confirmation',async()=>{
  const app=open(),individual=await app.save();await app.importReviews(await returnedReview('Sam',{3:feedback('Question')}));
  await app.saveInbox();await app.load(individual);
  let warned=false;await app.window.fire('beforeunload',{preventDefault:()=>warned=true});assert.equal(warned,true);
  app.window.confirm=()=>false;await app.ids['inbox-clear'].fire('click');assert.equal((await app.saveInbox()).reviews.length,1);
  app.window.confirm=()=>true;await app.ids['inbox-clear'].fire('click');assert.equal((await app.saveInbox()).reviews.length,0);
  assert.ok(app.states.every(e=>e.value==='not-reviewed'));
});

test('bounded inbox gives repair instructions and markup-looking feedback stays plain text',async()=>{
  const app=open(),review=await returnedReview('</script><img src=x>',{3:feedback('<b>Which?</b>')});
  await app.importReviews(review);assert.ok(app.inboxElements().some(e=>e.textContent==='<b>Which?</b>'));
  app.ids['inbox-import'].files=Array.from({length:13},()=>({size:1,text:()=>{throw Error('should not read');}}));
  await app.ids['inbox-import'].fire('change');assert.match(app.ids['inbox-status'].textContent,/at most 12 files/);
  assert.equal((await app.saveInbox()).reviews.length,1);
  app.ids['inbox-load'].files=[{size:40000001,text:()=>{throw Error('should not read');}}];await app.ids['inbox-load'].fire('change');
  assert.match(app.ids['inbox-status'].textContent,/exceeds 40 MB/);
  assert.equal((await app.saveInbox()).reviews.length,1);
});
