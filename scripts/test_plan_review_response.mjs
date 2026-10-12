import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open,openHTML,source,returnedReview} from './helpers/plan_review_harness.mjs';
const question = note => ({state:'question',note});
async function answer(app,index,row,text) {
  const control=app.control(`response-${index}-${row}`);control.value='answered';await control.fire('change');
  const note=app.control(`response-${index}-${row}-text`);note.value=text;await note.fire('input');
}
async function response(app,index=0) {
  const n=app.downloads.length;await app.control('reply-export-'+index).fire('click');
  return n===app.downloads.length ? undefined : JSON.parse(await app.downloads.at(-1).text());
}
async function load(app,packet) {
  app.ids['reply-load'].files=[new Blob([JSON.stringify(packet)])];await app.ids['reply-load'].fire('change');
}
const tree=e=>[e,...e.children.flatMap(tree)];
const replyText=app=>tree(app.ids.review).map(e=>e.textContent).join('\n');
async function fixture() {
  const app=open();const first=await returnedReview('Sam',{3:question('Which source?')});
  await app.importReviews(first,await returnedReview('PRIVATE REVIEWER',{3:question('PRIVATE OTHER NOTE')}));
  app.ids.preparer.value='Alex';await app.ids.preparer.fire('input');
  await answer(app,0,3,'Use source note 2. 🌓');await answer(app,1,3,'PRIVATE OTHER ANSWER');
  return {app,first};
}

test('selected response packet isolates other reviews and retains exact original snapshot and observations',async()=>{
  const {app,first}=await fixture(),before=await app.saveInbox(),packet=await response(app);
  assert.equal(packet.schema,'moonproj.plan-review-response.v1');assert.equal(packet.preparer,'Alex');
  assert.deepEqual(packet.review,first);assert.equal(packet.review.source_template,source);
  assert.deepEqual(packet.responses,[{review_index:0,annotation_index:3,disposition:'answered',response:'Use source note 2. 🌓'}]);
  assert.ok(!JSON.stringify(packet).includes('PRIVATE'));assert.deepEqual(await app.saveInbox(),before);
  assert.match(app.ids['inbox-status'].textContent,/download|Download/);
});

test('actual file response handback, reopen, revise and return to existing preparer inbox',async()=>{
  const {app,first}=await fixture();const packet=await response(app);
  const dir=mkdtempSync(join(tmpdir(),'moonproj-reply-'));
  try {
    writeFileSync(join(dir,'worksheet.html'),app.html);writeFileSync(join(dir,'response.json'),JSON.stringify(packet));
    const reviewer=openHTML(readFileSync(join(dir,'worksheet.html'),'utf8'));
    await load(reviewer,JSON.parse(readFileSync(join(dir,'response.json'),'utf8')));
    assert.equal(reviewer.ids.reviewer.value,'Sam');assert.equal(reviewer.notes[3].value,'Which source?');
    assert.match(replyText(reviewer),/Use source note 2\. 🌓/);assert.match(replyText(reviewer),/Original reviewer state: question/);
    assert.match(reviewer.ids['reply-status'].textContent,/no agreement or approval/);
    reviewer.notes[3].value='Source note 2 answers this question.';reviewer.states[3].value='no-change-requested';await reviewer.ids.review.fire('input');
    const revised=await reviewer.save();writeFileSync(join(dir,'revised.json'),await reviewer.downloads.at(-1).text());
    assert.equal(revised.annotations[3].note,'Source note 2 answers this question.');assert.equal(revised.source_template,source);
    assert.equal(packet.review.annotations[3].note,'Which source?','original response packet remains intact');
    await app.importReviews(readFileSync(join(dir,'revised.json'),'utf8'));const inbox=await app.saveInbox();
    assert.equal(inbox.reviews.length,3);assert.deepEqual(inbox.reviews[0].review,first);
    assert.deepEqual(inbox.reviews[2].review,revised);assert.equal(inbox.responses.at(-1).disposition,'open');
    assert.equal(inbox.responses[0].response,'Use source note 2. 🌓');
  } finally {rmSync(dir,{recursive:true,force:true});}
});

test('each numbered review has its own packet even with duplicate reviewer labels',async()=>{
  const app=open();await app.importReviews(await returnedReview('Sam',{3:question('First')}),await returnedReview('Sam',{4:question('Second')}));
  await answer(app,0,3,'First response');await answer(app,1,4,'Second response');
  const packet=await response(app,1);assert.equal(packet.review.annotations[4].note,'Second');
  assert.deepEqual(packet.responses,[{review_index:0,annotation_index:4,disposition:'answered',response:'Second response'}]);
  assert.ok(!JSON.stringify(packet).includes('First response'));
});

test('reply for one review can be exported while unrelated responses are unfinished',async()=>{
  const {app}=await fixture();const other=app.control('response-1-3-text');other.value='';await other.fire('input');
  assert.ok(await response(app,0));assert.equal(await response(app,1),undefined);
  assert.match(app.ids['inbox-status'].textContent,/explanation/);
});

test('wrong snapshot or incomplete response packet leaves current notes and replies unchanged',async()=>{
  const {app}=await fixture(),packet=await response(app),reviewer=open();await load(reviewer,packet);
  const original=await reviewer.save(),text=replyText(reviewer);
  const changed=structuredClone(packet);changed.review.source_template+=' ';await load(reviewer,changed);
  assert.match(reviewer.ids['reply-status'].textContent,/different exact plan snapshot/);
  const missing=structuredClone(packet);missing.responses=[];await load(reviewer,missing);
  assert.match(reviewer.ids['reply-status'].textContent,/incomplete/);
  assert.deepEqual(await reviewer.save(),original);assert.equal(replyText(reviewer),text);
});

test('reviewer can cancel replacement and loading ordinary notes clears old reply context',async()=>{
  const {app}=await fixture(),packet=await response(app),reviewer=open();await load(reviewer,packet);
  reviewer.notes[3].value='Unsaved follow-up';await reviewer.ids.review.fire('input');reviewer.window.confirm=()=>false;
  await load(reviewer,packet);assert.equal(reviewer.notes[3].value,'Unsaved follow-up');
  reviewer.window.confirm=()=>true;await reviewer.load(await returnedReview('Different',{3:question('New note')}));
  assert.ok(!replyText(reviewer).includes('Use source note 2.'));assert.equal(reviewer.ids['reply-status'].textContent,'');
});

test('pending response reads cannot overwrite newer reviewer edits or later notes loads',async()=>{
  const {app}=await fixture(),packet=await response(app),reviewer=open();let resolve;
  reviewer.ids['reply-load'].files=[{size:100,text:()=>new Promise(r=>resolve=r)}];
  const pending=reviewer.ids['reply-load'].fire('change');reviewer.notes[3].value='Keep this edit';await reviewer.ids.review.fire('input');
  resolve(JSON.stringify(packet));await pending;assert.equal(reviewer.notes[3].value,'Keep this edit');
  reviewer.ids['reply-load'].files=[{size:100,text:()=>new Promise(r=>resolve=r)}];const next=reviewer.ids['reply-load'].fire('change');
  await reviewer.load(await returnedReview('Newer'));resolve(JSON.stringify(packet));await next;assert.equal(reviewer.ids.reviewer.value,'Newer');
});

test('zero-feedback response packet resumes coverage without manufacturing agreement',async()=>{
  const app=open();const first=await returnedReview('Sam');await app.importReviews(first);const packet=await response(app);
  assert.deepEqual(packet.responses,[]);const reviewer=open();await load(reviewer,packet);
  assert.deepEqual(await reviewer.save(),first);assert.match(reviewer.ids['reply-status'].textContent,/no agreement or approval/);
});
