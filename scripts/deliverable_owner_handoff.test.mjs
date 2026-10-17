import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, mkdir, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { compileDeliverable, proposeOwnerHandoff, proposeCapacity, proposeSpecialists, verifyApproval, json } from './deliverable_workflow.mjs';
import { createDeliverableHost } from './deliverable_host.mjs';
import { mountDeliverablePanel } from '../frontend/opc_public/deliverable_panel.js';
import { harness } from './deliverable_panel_harness.mjs';
const now = '2026-10-13T00:00:00Z';
const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'handoff' }, workflow: { status: 'pending_review', accepted: false }, authority_effects: Object.fromEntries(['spend_authorized','accounting_posted','payment_released','contract_signed','work_executed'].map(k => [k,false])), owners: [{owner_id:'a',display_name:'Alex'},{owner_id:'b',display_name:'Bao'},{owner_id:'unused',display_name:'Casey'}], tasks: ['first','second','third'].map((id,i)=>({task_id:id,name:id,owner_id:i===1?'b':'a',dependencies:[],acceptance_gate_ids:[id]})), acceptance_gates:['first','second','third'].map(id=>({gate_id:id,scope_type:'task',scope_id:id,criteria:['Check '+id],required_evidence:['Evidence '+id]})) };
const options = { planText: json(plan), outcome: 'Source-backed handoff', workspaceRoot: '/tmp/fixture', modelSelector:'moongate/model',artifactRoot:'/tmp/fixture/data/deliverables',recordedAt:now, evidenceFiles:[{name:'source.md',content_base64:Buffer.from('Original evidence\r\n').toString('base64'),task_ids:['first']}] };
const proposal = (handoff, extra={}) => proposeOwnerHandoff({handoff,taskId:'first',ownerId:'b',reason:'Alex is unavailable',planText:options.planText,recordedAt:now,...extra});
test('owner handoff retains gates, dependencies, evidence and parent; changes actual Claw accountability',()=>{
 const parent=compileDeliverable(options), before=json(parent), child=proposal(parent);
 assert.equal(json(parent),before); assert.notEqual(child.execution_digest,parent.execution_digest);
 assert.equal(child.source.tasks[0].owner_id,'b'); assert.equal(child.source.tasks[0].owner_name,'Bao');
 assert.deepEqual(child.source.local_evidence,parent.source.local_evidence);
 assert.deepEqual(child.source.tasks.map(({owner_id,owner_name,...t})=>t),parent.source.tasks.map(({owner_id,owner_name,...t})=>t));
 assert.match(child.requests['inputs/first.json'].objective,/Bao \(b\)/);
 assert.equal(child.source.owner_handoffs[0].parent_execution_digest,parent.execution_digest);
 assert.throws(()=>verifyApproval(child,{contract_id:'moonproj.deliverable-review.v1',decision:'approved',execution_digest:parent.execution_digest,reviewer_id:'r',reviewed_at:now}),/exact named/);
 const next=proposal(child,{ownerId:'a',reason:'Alex returned'}); assert.equal(next.source.owner_handoffs.length,2); assert.equal(next.source.owner_handoffs[1].parent_id,child.id);
 assert.equal(proposal(parent,{ownerId:'unused'}).source.tasks[0].owner_name,'Casey');
});
test('handoff rejects unknown/no-op/blank/changed source and existing capacity scope',()=>{
 const h=compileDeliverable(options);
 for(const extra of [{ownerId:'missing'},{ownerId:'a'},{taskId:'missing'},{reason:' '},{reason:'x'.repeat(4097)},{planText:options.planText+' '}]) assert.throws(()=>proposal(h,extra));
 const capacity=proposeCapacity({handoff:h,ownerLimits:{a:1,b:1},recordedAt:now}); assert.throws(()=>proposal(capacity),/before capacity/);
 const specialized=proposeSpecialists({handoff:h,taskId:'first',recordedAt:now,specialists:['x','y'].map(task_id=>({task_id,name:task_id,owner_id:'a',acceptance_criteria:['Check'],required_evidence:['Notes']}))});assert.throws(()=>proposal(specialized),/before capacity/);
 const child=proposal(h); const capped=proposeCapacity({handoff:child,ownerLimits:{a:1,b:1},recordedAt:now});
 assert.equal(capped.source.capacity.assignments.find(t=>t.task_id==='first').owner_id,'b'); assert.equal(capped.source.owner_handoffs.length,1);
});
async function fixture(run){const root=await mkdtemp(path.join(os.tmpdir(),'owner-handoff-'));const config={data:path.join(root,'data'),config:async()=>({}),readOperatorJson:async()=>{throw Error('No approval')},runMoonflow:async()=>{throw Error('Forbidden native call')},now:()=>now};const api=createDeliverableHost(config);try{const input={...options,workspaceRoot:root};const preview=await api.act('preview',input);const board=await api.act('create',{...input,previewDigest:preview.execution_digest});await run({root,api,board,config});}finally{await rm(root,{recursive:true,force:true})}}
const body=board=>({id:board.id,taskId:'first',ownerId:'b',reason:'Owner unavailable'});
test('real durable host preview/save/restart/retry keeps exact original bytes and requires digest',()=>fixture(async({root,api,board,config})=>{
 const preview=await api.act('owner-handoff-preview',body(board));assert.equal((await api.list()).length,1);
 await assert.rejects(()=>api.act('owner-handoff',body(board)),/Preview/);
 await assert.rejects(()=>api.act('owner-handoff',{...body(board),reason:'Changed',previewDigest:preview.execution_digest}),/Preview/);
 const saved=await api.act('owner-handoff',{...body(board),previewDigest:preview.execution_digest});assert.equal(saved.status,'awaiting_import');
 const restarted=createDeliverableHost(config);assert.equal((await restarted.act('owner-handoff',{...body(board),previewDigest:preview.execution_digest})).id,saved.id);assert.equal((await restarted.list()).length,2);
 const base=path.join(root,'data/deliverables');for(const ref of ['source-plan.json',board.source.local_evidence.files[0].artifact_ref])assert.deepEqual(await readFile(path.join(base,board.id,ref)),await readFile(path.join(base,saved.id,ref)));
 await assert.rejects(()=>restarted.act('prepare',{id:saved.id}),/deliverable_review_file/);
 const projection=path.join(base,board.id,'.moonsuite/products/moonflow/runs',board.id,'projection.json');await mkdir(path.dirname(projection),{recursive:true});await writeFile(projection,'{}');
 await assert.rejects(()=>api.act('owner-handoff-preview',body(board)),/unimported board/);
}));
test('changed evidence blocks child save rather than copying damaged bytes',()=>fixture(async({root,api,board})=>{const preview=await api.act('owner-handoff-preview',body(board));await writeFile(path.join(root,'data/deliverables',board.id,board.source.local_evidence.files[0].artifact_ref),'changed');await assert.rejects(()=>api.act('owner-handoff',{...body(board),previewDigest:preview.execution_digest}),/changed/)}));
test('mounted actual panel previews changed owner, invalidates on edits and saves reviewed child',()=>fixture(async({api})=>{
 const h=harness();const requests=[];const fetcher=async(url,opts)=>{if(!opts)return{ok:true,json:async()=>({deliverables:await api.list()})};const b=JSON.parse(opts.body);requests.push({url,b});try{return{ok:true,json:async()=>await api.act(url.split('/').at(-1),b)}}catch(error){return{ok:false,json:async()=>({error:error.message})}}};
 const dispose=mountDeliverablePanel(h.host,{fetcher});try{await new Promise(r=>setTimeout(r,15));h.input('handoffTask','first');h.input('handoffOwner','b');h.input('handoffReason','Need coverage');await h.click('owner-handoff-preview');assert.equal(h.get('[data-action="owner-handoff"]').disabled,false);assert.match(h.host.innerHTML,/previous_owner_name/);
 const stale=h.get('[data-action="owner-handoff"]');h.input('handoffReason','Changed reason');assert.equal(h.get('[data-action="owner-handoff"]').disabled,true);await h.click('owner-handoff');assert.equal((await api.list()).length,1);
 await stale.events.click();assert.equal((await api.list()).length,1);await h.click('owner-handoff-preview');await h.click('owner-handoff');assert.equal((await api.list()).length,2);assert.match(h.host.innerHTML,/Owner handoff history/);assert.match(h.host.innerHTML,/separate review-pending/);
 }finally{dispose()}
}));

test('cancelled in-flight owner preview cannot restore stale scope or change a newer draft',()=>fixture(async({api})=>{
 const h=harness();let release;const delayed=new Promise(resolve=>{release=resolve});
 const fetcher=async(url,opts)=>{if(!opts)return{ok:true,json:async()=>({deliverables:await api.list()})};const value=await api.act(url.split('/').at(-1),JSON.parse(opts.body));await delayed;return{ok:true,json:async()=>value}};
 const dispose=mountDeliverablePanel(h.host,{fetcher});try{await new Promise(r=>setTimeout(r,15));h.input('handoffTask','first');h.input('handoffOwner','b');h.input('handoffReason','Old reason');const old=h.click('owner-handoff-preview');await new Promise(r=>setTimeout(r,0));await h.click('cancel-draft');h.input('handoffOwner','unused');h.input('handoffReason','New reason');release();await old;assert.equal(h.get('[data-action="owner-handoff"]').disabled,true);assert.equal(h.get('[data-field="handoffOwner"]').value,'unused');assert.doesNotMatch(h.host.innerHTML,/Owner handoff ready to inspect/);assert.equal((await api.list()).length,1)}finally{release();dispose()}
}));

test('cancel clears a completed handoff preview and a repeated preview cannot reveal old save state',()=>fixture(async({api})=>{
 const h=harness();let release;let previews=0;let saves=0;const delayed=new Promise(resolve=>{release=resolve});
 const fetcher=async(url,opts)=>{if(!opts)return{ok:true,json:async()=>({deliverables:await api.list()})};if(url.endsWith('/owner-handoff'))saves++;const value=await api.act(url.split('/').at(-1),JSON.parse(opts.body));if(url.endsWith('/owner-handoff-preview')&&++previews===3)await delayed;return{ok:true,json:async()=>value}};
 const dispose=mountDeliverablePanel(h.host,{fetcher});const fill=()=>{h.input('handoffTask','first');h.input('handoffOwner','b');h.input('handoffReason','Need coverage')};
 try{await new Promise(r=>setTimeout(r,15));fill();await h.click('owner-handoff-preview');assert.equal(h.get('[data-action="owner-handoff"]').disabled,false);await h.click('cancel-draft');assert.equal(h.get('[data-action="owner-handoff"]').disabled,true);assert.equal(h.get('[data-field="handoffOwner"]').value,'');await h.click('owner-handoff');assert.equal(saves,0);
 fill();await h.click('owner-handoff-preview');const oldSave=h.get('[data-action="owner-handoff"]');const pending=h.click('owner-handoff-preview');await new Promise(r=>setTimeout(r,0));await h.click('cancel-draft');assert.equal(h.get('[data-action="owner-handoff"]').disabled,true);release();await pending;await oldSave.events.click();await h.click('owner-handoff');assert.equal(saves,0);assert.equal((await api.list()).length,1)
 }finally{release();dispose()}
}));
