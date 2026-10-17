import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { compileDeliverable, projectDeliverable, prepareInvocation, proposeRework, proposeCapacity, proposeSpecialists, verifyApproval, json, sha } from './deliverable_workflow.mjs';
import { createDeliverableHost } from './deliverable_host.mjs';
import { renderDeliverablePanel, mountDeliverablePanel, specialistRows } from '../frontend/opc_public/deliverable_panel.js';

const timestamp = '2026-10-12T09:00:00Z';
function plan() {
  return { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'project-one' },
    workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'owner-a', display_name: 'Alex' }, { owner_id: 'owner-b', display_name: 'Bao' }],
    tasks: [
      { task_id: 'research', name: 'Gather source facts', owner_id: 'owner-a', milestone_id: 'm1', dependencies: [], acceptance_gate_ids: ['research-gate'] },
      { task_id: 'design', name: 'Prepare design', owner_id: 'owner-b', milestone_id: 'm1', dependencies: [], acceptance_gate_ids: ['design-gate'] },
      { task_id: 'write', name: 'Write brief', owner_id: 'owner-a', milestone_id: 'm1', dependencies: ['research', 'design'], acceptance_gate_ids: ['write-gate'] },
    ], acceptance_gates: ['research', 'design', 'write'].map(id => ({ gate_id: `${id}-gate`, scope_type: 'task', scope_id: id,
      criteria: [`${id} criterion is met`], required_evidence: [`${id} output text`] })) };
}
const make = (value = plan()) => compileDeliverable({ planText: json(value), outcome: 'A reviewed launch brief', workspaceRoot: '/tmp/approved', modelSelector: 'moongate/approved-model', recordedAt: timestamp, artifactRoot: '/tmp/approved/data/deliverables' });
function projectionFor(handoff) {
  return { protocol: 'moonflow.run-projection.v3', run_id: handoff.id, book_id: handoff.graph.book_id, source_digest: handoff.execution_digest,
    items: handoff.graph.items.map(item => ({ ...structuredClone(item), status: 'ready', attempt_count: 0, request_id: '', active_attempt_id: '', attempt_status: '', result_id: '', output_digest: '', artifacts: [], acceptance_review_id: '', acceptance_reviewer_id: '', acceptance_review_artifact: '' })) };
}
const reviewFor = handoff => ({ contract_id: 'moonproj.deliverable-review.v1', decision: 'approved', execution_digest: handoff.execution_digest, reviewer_id: 'operator', reviewed_at: timestamp, provider_calls_approved: false });

test('native plan becomes an owned dependency graph without declaring execution or authenticated assignment', () => {
  const handoff = make();
  assert.deepEqual(handoff.graph.items[2].depends_on, ['research', 'design']);
  assert.deepEqual(handoff.graph.items[2].acceptance_criteria, ['write criterion is met']);
  assert.equal(handoff.source.tasks[1].owner_name, 'Bao');
  assert.equal(handoff.requests['inputs/research.json'].role, 'mooncode');
  assert.equal(handoff.requests['inputs/write.json'].profile.web_search, false);
  assert.match(handoff.requests['inputs/write.json'].profile.instructions[1], /projection.json/);
  assert.equal(projectDeliverable(handoff, null).tasks[0].dispatchable, false);
  assert.equal(projectDeliverable(handoff, null).status, 'awaiting_import');
  assert.equal(make().id, handoff.id);
});

test('invalid graph ownership, missing prerequisites, cycles, scoped criteria and authority fail closed', () => {
  for (const mutate of [
    p => { p.tasks[0].task_id = '..'; },
    p => { p.tasks[0].owner_id = 'unknown'; },
    p => { p.tasks[0].dependencies = ['missing']; },
    p => { p.tasks[0].dependencies = ['write']; },
    p => { p.tasks.push(p.tasks[0]); },
    p => { p.acceptance_gates[0].scope_id = 'design'; },
    p => { p.acceptance_gates[0].criteria = []; },
    p => { p.authority_effects.work_executed = true; },
  ]) { const p = plan(); mutate(p); assert.throws(() => make(p)); }
});

test('exact operator review binds model, owner, dependencies and outcome; global configuration is not provider approval', () => {
  const handoff = make(), review = reviewFor(handoff);
  assert.equal(verifyApproval(handoff, review).reviewer_id, 'operator');
  assert.throws(() => verifyApproval(handoff, review, true), /explicit approval/);
  assert.throws(() => verifyApproval(handoff, { ...review, execution_digest: sha('another') }), /exact named/);
  const changed = structuredClone(handoff); changed.source.tasks[0].owner_id = 'other';
  assert.throws(() => verifyApproval(changed, review), /scope changed/);
});

test('foreign projections and altered declared dependencies never present ready work', () => {
  const handoff = make(), projection = projectionFor(handoff);
  assert.throws(() => projectDeliverable(handoff, { ...projection, source_digest: sha('old') }), /exact deliverable/);
  projection.items[2].depends_on = [];
  assert.throws(() => projectDeliverable(handoff, projection), /declaration changed/);
});

// The following harness deliberately simulates native Flow/Claw responses. It
// exercises real MoonProj orchestration and durable files, not native import or
// service acceptance. No provider, company database, or model is contacted.
async function fixture(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'moonproj-deliverable-'));
  const settings = { workspace_root: directory, model_selector: 'moongate/approved-model', deliverable_review_file: path.join(directory, 'review.json'), moonflow_binary: '/fixture/moonflow', catalog_file: path.join(directory, 'catalog.json'), moonclaw_gateway: 'http://127.0.0.1:18999' };
  const calls = [], submits = [], submittedInvocations = [], controls = { timeout: false, lost: false, noContent: false, remoteStatus: 'succeeded', currentTime: timestamp, failImport: false, failAfterPrepare: false, factoryError: false };
  const rootFor = id => path.join(directory, 'data/deliverables', id);
  const projectionPath = id => path.join(rootFor(id), `.moonsuite/products/moonflow/runs/${id}/projection.json`);
  const readProjection = async id => JSON.parse(await readFile(projectionPath(id), 'utf8'));
  const put = async (file, value) => { await mkdir(path.dirname(file), { recursive: true }); await writeFile(file, typeof value === 'string' ? value : json(value)); };
  const getHandoff = async id => JSON.parse(await readFile(path.join(rootFor(id), 'handoff.json'), 'utf8'));
  async function fakeFlow(binary, args) {
    calls.push(args[0]);
    const [action, root, idOrGraph] = args;
    if (action === 'validate-work-graph-capabilities') {
      const graph = JSON.parse(await readFile(args[1], 'utf8')), catalog = JSON.parse(await readFile(args[2], 'utf8'));
      const op = catalog.operations?.find(o => o.operation_ref === graph.items[0].operation);
      const accepted = catalog.conformant === true && Boolean(op) && op.health_checked_at <= args[3] && op.health_valid_until >= args[3] &&
        op.authority === graph.items[0].requested_authority && op.adapter_id === 'moonclaw-agent-goal-v1';
      return { contract_id: 'moonflow.graph-capability-report.v1', graph_id: graph.graph_id, catalog_id: catalog.catalog_id, accepted,
        bindings: accepted ? graph.items.map(item => ({ work_item_id: item.work_item_id, operation_ref: item.operation, adapter_id: op.adapter_id,
          input_schema_ref: op.input_schema_ref, output_schema_ref: op.output_schema_ref, authority: op.authority, claim_ceiling: op.claim_ceiling, review_required: op.review_required })) : [] };
    }
    if (action === 'import-conformant-graph') {
      if (controls.failImport) throw Error('Fixture native import unavailable');
      const graph = JSON.parse(await readFile(idOrGraph, 'utf8'));
      await put(projectionPath(graph.graph_id), projectionFor(await getHandoff(graph.graph_id)));
      return {};
    }
    const id = idOrGraph, projection = await readProjection(id);
    if (action === 'prepare-next') {
      for (const item of projection.items) if (item.status === 'ready' && item.depends_on.every(dep => projection.items.find(i => i.work_item_id === dep).status === 'accepted')) {
        const refs = [...new Set([...item.input_artifacts, ...item.depends_on.flatMap(dep => projection.items.find(i => i.work_item_id === dep).artifacts)])];
        const parts = [];
        for (const ref of refs) parts.push(`${ref}|${sha(await readFile(path.join(root, ref)))}`);
        const digest = sha(parts.join('\n'));
        Object.assign(item, { status: 'active', attempt_count: 1, request_id: `request-${id}-${item.work_item_id}-a1`, active_attempt_id: `attempt-${item.work_item_id}-1`, idempotency_key: `${id}/${item.work_item_id}/1/${digest}`, input_digest: digest, attempt_status: 'submitted' });
        const request = { ...item, run_id: id, book_id: projection.book_id, attempt_id: item.active_attempt_id, input_artifacts: refs, created_at: args[4] };
        await put(path.join(root, `.moonsuite/products/moonflow/runs/${id}/dispatch/${item.request_id}.request.json`), request);
      }
    } else if (action === 'reconcile-attempt') {
      const receipt = JSON.parse(await readFile(args[3], 'utf8'));
      const item = projection.items.find(i => i.request_id === receipt.request_id);
      assert.ok(item, 'fixture result must match a prepared native request');
      const states = { submitted: 'active', running: 'active', succeeded: 'review', failed: 'failed', cancelled: 'cancelled', unknown: 'blocked' };
      assert.ok(states[receipt.status], 'fixture must use an actual native attempt status');
      Object.assign(item, { status: states[receipt.status], attempt_status: receipt.status, result_id: receipt.result_id,
        output_digest: receipt.status === 'succeeded' ? receipt.output_digest : item.output_digest,
        artifacts: [...new Set([...item.artifacts, ...receipt.output_artifacts])],
        blocker: receipt.status === 'unknown' ? 'adapter outcome unknown; reconciliation required' : receipt.error_kind || '' });
    } else throw Error(`Unknown fixture command ${action}`);
    await put(projectionPath(id), projection);
    if (action === 'prepare-next' && controls.failAfterPrepare) throw Error('Fixture interrupted after native preparation');
    return projection;
  }
  const receipts = new Map(), successReceipts = new Map();
  const gatewayFactory = () => {
    if (controls.factoryError) throw Error('Fixture gateway configuration rejected before submission');
    return async (action, invocation) => {
    const request = invocation.request, key = request.request_id;
    if (action === 'submit') {
      submits.push(key); submittedInvocations.push(structuredClone(invocation));
      const ref = `outputs/${request.work_item_id}.md`, text = `# ${request.work_item_id}\nReviewed content for ${request.run_id}\n`;
      await put(path.join(rootFor(request.run_id), ref), text);
      const goalRef = `.moonsuite/products/moonclaw/agent-goal-receipts/${request.work_item_id}.json`;
      const journalRef = `.moonsuite/products/moonclaw/mooncode/sessions/${invocation.input.session_id}/journal.jsonl`;
      const journal = json({ artifact_ref: ref }); await put(path.join(rootFor(request.run_id), journalRef), journal);
      const goal = json({ contract_id: 'moonclaw.agent-goal-execution-receipt.v1', operation_ref: request.operation,
        execution_status: 'succeeded', goal_outcome: 'achieved', acceptance_status: 'review-required',
        session_id: invocation.input.session_id, goal_id: invocation.input.goal_id, receipt_ref: goalRef, journal_ref: journalRef,
        artifact_evidence: [{ ref: journalRef, digest: sha(journal) }, ...(controls.noContent ? [] : [{ ref, digest: sha(text) }])] });
      await put(path.join(rootFor(request.run_id), goalRef), goal);
      assert.equal(invocation.input.workspace_root, rootFor(request.run_id), 'goal and gateway artifacts share the exact Flow run root');
      const receipt = { contract_id: 'moonclaw.capability-invocation-receipt.v1', request_id: key, attempt_id: request.attempt_id, idempotency_key: request.idempotency_key,
        product_id: request.product_id, operation_ref: request.operation, adapter_id: invocation.adapter_id, input_digest: request.input_digest,
        status: 'succeeded', result_id: `result-${request.attempt_id}`, output_digest: sha(`${goalRef}|${sha(goal)}\n${journalRef}|${sha(journal)}`), output_artifacts: [goalRef, journalRef], external_job_id: 'fixture-job', error_kind: '', compensable: false, recorded_at: timestamp };
      successReceipts.set(key, receipt);
      const returned = controls.remoteStatus === 'succeeded' ? receipt : { ...receipt, status: controls.remoteStatus, result_id: `${receipt.result_id}-${controls.remoteStatus}`, output_digest: '', output_artifacts: [], error_kind: controls.remoteStatus === 'failed' ? 'fixture-adapter-failure' : '' };
      receipts.set(key, returned);
      if (controls.timeout) throw Error('fixture timeout after submit');
      return returned;
    }
    if (action === 'reconcile' && controls.remoteStatus === 'succeeded' && successReceipts.has(key)) receipts.set(key, successReceipts.get(key));
    if (controls.lost) return null;
    return receipts.get(key) || null;
    };
  };
  await put(settings.catalog_file, { contract_id: 'moonflow.capability-catalog.v1', catalog_id: 'fixture-catalog', compiled_at: timestamp, conformant: true,
    products: [{ product_id: 'moonclaw', pack_id: 'moonclaw', pack_version: '0.1.5' }], issues: [], operations: [{
      operation_ref: 'moonclaw/agent.goal.execute@0.1.5', product_id: 'moonclaw', pack_id: 'moonclaw', pack_version: '0.1.5', tool_id: 'agent.goal.execute', adapter_id: 'moonclaw-agent-goal-v1',
      protocol: 'moonflow.adapter.v2', authority: 'workspace-mutation', input_schema_ref: 'moonclaw/agent-goal-execution-request@1.0.0', output_schema_ref: 'moonclaw/agent-goal-execution-receipt@1.0.0',
      claim_ceiling: 'digital-artifact', idempotent: true, review_required: true, supports_cancel: true, supports_reconcile: true,
      health_checked_at: timestamp, health_valid_until: '2026-10-12T10:00:00Z', health_evidence_ref: 'health/fixture.json', health_evidence_digest: sha('fixture-health-only'),
    }] });
  const api = createDeliverableHost({ data: path.join(directory, 'data'), config: async () => settings,
    readOperatorJson: async file => JSON.parse(await readFile(file, 'utf8')), runMoonflow: fakeFlow, now: () => controls.currentTime, gatewayFactory });
  async function create() {
    return api.act('create', { planText: json(plan()), outcome: 'A reviewed launch brief', workspaceRoot: directory, modelSelector: settings.model_selector });
  }
  async function approve(id, provider = false) { settings.moonclaw_workspace_root = rootFor(id); const handoff = await getHandoff(id); await put(settings.deliverable_review_file, { ...reviewFor(handoff), provider_calls_approved: provider }); }
  async function accept(id, taskId) {
    const p = await readProjection(id), item = p.items.find(i => i.work_item_id === taskId);
    assert.equal(item.status, 'review', 'synthetic review must not precede output');
    const ref = `reviews/${taskId}.json`, review = { contract_id: 'moonflow.acceptance-review.v1', decision: 'accepted', review_id: `review-${taskId}`, reviewer_id: 'independent-reviewer', review_authority_id: 'fixture-only',
      run_id: id, work_item_id: taskId, declaration_id: item.declaration_id, result_id: item.result_id, attempt_id: item.active_attempt_id, output_digest: item.output_digest, receipt_artifact: ref,
      criteria: item.acceptance_criteria.map(criterion => ({ criterion, satisfied: true, evidence_refs: [...item.artifacts], note: 'Synthetic reviewer checked fixture output' })) };
    await put(path.join(rootFor(id), ref), review);
    Object.assign(item, { status: 'accepted', acceptance_review_id: review.review_id, acceptance_reviewer_id: review.review_authority_id, acceptance_review_artifact: ref, artifacts: [...item.artifacts, ref] });
    await put(projectionPath(id), p);
  }
  try { return await run({ api, directory, settings, create, approve, accept, rootFor, getHandoff, put, readProjection, projectionPath, submits, submittedInvocations, calls, controls }); }
  finally { await rm(directory, { recursive: true, force: true }); }
}

test('fixture workflow: outcome → owned parallel tasks → reviewed dependencies → ready dispatch → assembled actual bytes', () => fixture(async f => {
  const board = await f.create();
  assert.equal(board.status, 'awaiting_import');
  assert.deepEqual(f.calls, []);
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /ENOENT/);
  await f.approve(board.id);
  let current = await f.api.act('prepare', { id: board.id });
  assert.deepEqual(current.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['research', 'design']);
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'research' }), /explicit approval/);
  await f.approve(board.id, true);
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'write' }), /active MoonFlow/);
  await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  current = await f.api.act('prepare', { id: board.id });
  assert.equal(current.tasks.find(t => t.task_id === 'write').dispatchable, false, 'execution success is not prerequisite acceptance');
  await assert.rejects(() => f.api.act('assemble', { id: board.id }), /named review/);
  await f.accept(board.id, 'research');
  await f.api.act('dispatch', { id: board.id, taskId: 'design' }); await f.accept(board.id, 'design');
  current = await f.api.act('prepare', { id: board.id });
  assert.equal(current.tasks.find(t => t.task_id === 'write').dispatchable, true);
  await f.api.act('dispatch', { id: board.id, taskId: 'write' }); await f.accept(board.id, 'write');
  const assembled = await f.api.act('assemble', { id: board.id });
  assert.equal(assembled.assembly.entries.length, 3); assert.equal(assembled.assembly.customer_accepted, false);
  assert.match(assembled.text, /Reviewed content/);
  assert.equal((await f.api.act('assemble', { id: board.id })).assembly.content_digest, assembled.assembly.content_digest);
  assert.equal(f.submits.length, 3);
}));

test('fixture workflow: timeout/restart uses one attempt and never submits again while the outcome is unknown', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  f.controls.timeout = true; f.controls.lost = true;
  const first = await f.api.act('dispatch', { id: board.id, taskId: 'research' }); assert.equal(first.dispatch.status, 'unknown');
  const unknown = await f.api.act('dispatch', { id: board.id, taskId: 'research' }); assert.equal(unknown.dispatch.status, 'unknown');
  assert.equal(f.submits.length, 1);
  f.controls.lost = false;
  const recovered = await f.api.act('dispatch', { id: board.id, taskId: 'research' }); assert.equal(recovered.dispatch.status, 'succeeded');
  assert.equal(recovered.tasks.find(t => t.task_id === 'research').accepted, false);
  assert.equal(f.submits.length, 1);
}));

async function finish(f, id) {
  await f.approve(id, true); await f.api.act('prepare', { id });
  for (const task of ['research', 'design']) { await f.api.act('dispatch', { id, taskId: task }); await f.accept(id, task); }
  await f.api.act('prepare', { id }); await f.api.act('dispatch', { id, taskId: 'write' }); await f.accept(id, 'write');
}

test('fixture workflow: targeted correction invalidates its downstream output and retains unrelated reviewed bytes', () => fixture(async f => {
  const board = await f.create(); await finish(f, board.id);
  const before = await f.api.act('assemble', { id: board.id });
  const child = await f.api.act('rework', { id: board.id, taskId: 'research', reason: 'Correct the market size and update the final brief' });
  assert.deepEqual(child.tasks.map(t => t.task_id), ['research', 'write']);
  assert.deepEqual(child.graph.items[1].depends_on, ['research']);
  assert.equal(child.status, 'awaiting_import');
  assert.equal(child.source.rework.retained[0].task_id, 'design');
  assert.ok(child.graph.items[0].input_artifacts.some(ref => ref.startsWith('retained/design/')));
  await assert.rejects(() => f.api.act('prepare', { id: child.id }), /exact named/);
  await f.approve(child.id, true); await f.api.act('prepare', { id: child.id });
  await f.api.act('dispatch', { id: child.id, taskId: 'research' }); await f.accept(child.id, 'research');
  await f.api.act('prepare', { id: child.id }); await f.api.act('dispatch', { id: child.id, taskId: 'write' }); await f.accept(child.id, 'write');
  const after = await f.api.act('assemble', { id: child.id });
  assert.equal(after.assembly.entries.length, 3); assert.match(after.text, /Retained: Prepare design/);
  assert.equal((await f.api.act('assemble', { id: board.id })).text, before.text);
  const grandchild = await f.api.act('rework', { id: child.id, taskId: 'write', reason: 'Shorten the brief only' });
  assert.deepEqual(grandchild.tasks.map(t => t.task_id), ['write']);
  assert.equal(grandchild.source.rework.carried_artifacts.length, 2);
  const repeat = await f.api.act('rework', { id: child.id, taskId: 'write', reason: 'Shorten the brief only' });
  assert.equal(repeat.id, grandchild.id);
}));

test('fixture integrity: modified outputs or symlinked artifacts block assembly and retained reuse', () => fixture(async f => {
  const board = await f.create(); await finish(f, board.id);
  const file = path.join(f.rootFor(board.id), 'outputs/design.md');
  const prior = await readFile(file, 'utf8'); await writeFile(file, 'changed');
  await assert.rejects(() => f.api.act('assemble', { id: board.id }), /bytes changed/);
  await assert.rejects(() => f.api.act('rework', { id: board.id, taskId: 'research', reason: 'Correct source' }), /bytes changed/);
  await writeFile(file, prior); await rm(file); await symlink(path.join(f.rootFor(board.id), 'outputs/research.md'), file);
  await assert.rejects(() => f.api.act('assemble', { id: board.id }), /symlink/);
}));

test('fixture integrity: changed review identity and fake accepted prerequisite are rejected', () => fixture(async f => {
  const board = await f.create(); await finish(f, board.id);
  const file = path.join(f.rootFor(board.id), 'reviews/design.json');
  const review = JSON.parse(await readFile(file, 'utf8')); review.result_id = 'another-result'; await f.put(file, review);
  await assert.rejects(() => f.api.act('assemble', { id: board.id }), /Named review/);
  const p = await f.readProjection(board.id); p.items[0].status = 'review';
  const handoff = await f.getHandoff(board.id);
  assert.throws(() => projectDeliverable(handoff, p), /unaccepted prerequisites/);
}));

test('fixture controls and exact-input binding: pause and altered prepared fields block any gateway call', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  const control = path.join(f.rootFor(board.id), `.moonsuite/products/moonflow/runs/${board.id}/control.json`);
  await f.put(control, { contract_id: 'moonflow.run-control.v1', run_id: board.id, state: 'paused', authority_ceiling: '' });
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'research' }), /run control/);
  await rm(control);
  const p = await f.readProjection(board.id), task = p.items[0];
  const file = path.join(f.rootFor(board.id), `.moonsuite/products/moonflow/runs/${board.id}/dispatch/${task.request_id}.request.json`);
  const request = JSON.parse(await readFile(file, 'utf8')); request.requested_authority = 'external-effect'; await f.put(file, request);
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'research' }), /Prepared request differs/);
  assert.equal(f.submits.length, 0);
}));

test('fixture recovery: duplicate create restores saved board without import or overwriting source; config drift blocks work', () => fixture(async f => {
  const first = await f.create(), second = await f.create(); assert.equal(first.id, second.id);
  assert.equal((await f.api.list()).length, 1); assert.deepEqual(f.calls, []);
  await f.approve(first.id, true); f.settings.model_selector = 'moongate/other';
  await assert.rejects(() => f.api.act('prepare', { id: first.id }), /differs/);
}));

test('production panel exposes owned prerequisites, exact status, rework and assembly with escaped text', () => {
  const handoff = make(), entry = { ...projectDeliverable(handoff, null), source: handoff.source, graph: handoff.graph, execution_digest: handoff.execution_digest };
  entry.tasks[0].name = '<script>alert(1)</script>';
  const html = renderDeliverablePanel({ entries: [entry], selected: entry.id, draft: { outcome: '<unsafe>', planText: '</textarea>', workspaceRoot: '/tmp', modelSelector: 'model', reason: '' }, busy: false, error: '', notice: '', assembly: '' });
  assert.match(html, /Delegate a deliverable/); assert.match(html, /owner: Alex/); assert.match(html, /research, design/);
  assert.match(html, /data-action="prepare"/); assert.match(html, /data-action="rework"/);
  assert.doesNotMatch(html, /<script>alert/); assert.match(html, /&lt;\/textarea&gt;/);
  assert.match(html, /data-action="assemble" disabled/);
});

test('production panel disposal ignores a late disconnected-host response', async () => {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  const host = { innerHTML: '', querySelectorAll: () => [], querySelector: () => null };
  const dispose = mountDeliverablePanel(host, { fetcher: () => promise });
  const html = host.innerHTML; dispose();
  resolve({ ok: true, json: async () => ({ deliverables: [{ id: 'late', outcome: 'Late response' }] }) });
  await new Promise(r => setImmediate(r));
  assert.equal(host.innerHTML, html);
});

test('milestone-wide criteria require explicit per-task adaptation before becoming execution acceptance', () => {
  const value = plan(); value.acceptance_gates[0].scope_type = 'milestone'; value.acceptance_gates[0].scope_id = 'm1';
  assert.throws(() => make(value), /Task-specific acceptance is required for research/);
  const handoff = compileDeliverable({ planText: json(value), outcome: 'A brief', workspaceRoot: '/tmp/approved', artifactRoot: '/tmp/approved/data', modelSelector: 'moongate/model', recordedAt: timestamp,
    taskCriteria: { research: { criteria: ['Check three sources'], required_evidence: ['Source notes'] } } });
  assert.deepEqual(handoff.graph.items[0].acceptance_criteria, ['Check three sources']);
});

test('fixture integrity: a receipt and journal without produced artifact evidence cannot stand in for a deliverable', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  f.controls.noContent = true;
  await f.api.act('dispatch', { id: board.id, taskId: 'research' }); await f.accept(board.id, 'research');
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /no content-digested deliverable artifacts/);
}));

test('fixture integrity: modified prepared input bytes block before any provider call', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  await writeFile(path.join(f.rootFor(board.id), 'inputs/research.json'), '{}');
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'research' }), /Prepared input bytes changed/);
  assert.equal(f.submits.length, 0);
}));

test('fixture interruption: concurrent dispatch clicks are serialized and never duplicate submission', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  const results = await Promise.allSettled([f.api.act('dispatch', { id: board.id, taskId: 'research' }), f.api.act('dispatch', { id: board.id, taskId: 'research' })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.match(results.find(r => r.status === 'rejected').reason.message, /operation in progress/);
  assert.equal(f.submits.length, 1);
}));

test('fixture recovery: an interrupted local materialization is repaired by repeating the same create', () => fixture(async f => {
  const board = await f.create();
  await rm(path.join(f.rootFor(board.id), 'inputs/research.json'));
  await rm(path.join(f.rootFor(board.id), 'source-plan.json'));
  const restored = await f.create();
  assert.equal(restored.id, board.id);
  assert.equal(JSON.parse(await readFile(path.join(f.rootFor(board.id), 'inputs/research.json'), 'utf8')).contract_id, 'moonclaw.agent-goal-execution-request.v1');
  assert.equal(JSON.parse(await readFile(path.join(f.rootFor(board.id), 'source-plan.json'), 'utf8')).contract_id, 'moonproj.project-plan-artifact.v1');
  assert.deepEqual(f.calls, []);
}));

test('native blocked/unknown receipt remains reconcilable and forbids rework until the original effect is established', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  await f.api.act('dispatch', { id: board.id, taskId: 'design' }); await f.accept(board.id, 'design');
  f.controls.remoteStatus = 'unknown';
  const unknown = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  const task = unknown.tasks.find(t => t.task_id === 'research');
  assert.equal(task.status, 'blocked'); assert.equal(task.attempt_status, 'unknown');
  assert.equal(task.dispatchable, false); assert.equal(task.reconcilable, true);
  await assert.rejects(() => f.api.act('rework', { id: board.id, taskId: 'research', reason: 'Try another execution' }), /uncertain work/);
  const html = renderDeliverablePanel({ entries: [unknown], selected: board.id, draft: {}, busy: false, error: '', notice: '', assembly: '' });
  assert.match(html, /Reconcile same attempt:/);
  const stillUnknown = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(stillUnknown.tasks.find(t => t.task_id === 'research').status, 'blocked');
  assert.equal(f.submits.length, 2, 'only design and the original research were submitted');
  f.controls.remoteStatus = 'succeeded';
  const recovered = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(recovered.tasks.find(t => t.task_id === 'research').status, 'review');
  assert.equal(f.submits.length, 2);
  assert.equal(recovered.tasks.find(t => t.task_id === 'write').dispatchable, false, 'recovered success still awaits review');
}));

test('native blocked/unknown without a local dispatch journal still never authorizes submit', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  const projection = await f.readProjection(board.id), task = projection.items[0];
  Object.assign(task, { status: 'blocked', attempt_status: 'unknown', result_id: 'external-unknown-receipt', blocker: 'adapter outcome unknown; reconciliation required' });
  await f.put(f.projectionPath(board.id), projection); f.controls.lost = true;
  const unresolved = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(unresolved.dispatch.status, 'unknown'); assert.equal(f.submits.length, 0);
  assert.equal(unresolved.tasks[0].reconcilable, true);
}));

test('native failed and cancelled receipts are terminal states rather than active retries', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  for (const [taskId, status] of [['research', 'failed'], ['design', 'cancelled']]) {
    f.controls.remoteStatus = status;
    const current = await f.api.act('dispatch', { id: board.id, taskId });
    const task = current.tasks.find(t => t.task_id === taskId);
    assert.equal(task.status, status); assert.equal(task.reconcilable, false); assert.equal(task.dispatchable, false);
  }
  assert.equal(f.submits.length, 2);
}));

async function refreshCatalog(f, checked = '2026-10-12T11:00:00Z', until = '2026-10-12T12:00:00Z') {
  const catalog = JSON.parse(await readFile(f.settings.catalog_file, 'utf8'));
  catalog.compiled_at = checked; catalog.conformant = true;
  Object.assign(catalog.operations[0], { health_checked_at: checked, health_valid_until: until, health_evidence_ref: 'health/refreshed.json', health_evidence_digest: sha(`refreshed-${checked}`) });
  await f.put(f.settings.catalog_file, catalog); return catalog;
}

test('catalog recovery: rejected first candidate and failed first import do not poison the saved board', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true);
  const catalog = JSON.parse(await readFile(f.settings.catalog_file, 'utf8')); catalog.conformant = false; await f.put(f.settings.catalog_file, catalog);
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /does not validate/);
  assert.equal((await f.api.state(board.id)).status, 'awaiting_import');
  await assert.rejects(() => readFile(path.join(f.rootFor(board.id), 'flow/capability-catalog.json')), /ENOENT/);
  await refreshCatalog(f, timestamp, '2026-10-12T10:00:00Z'); f.controls.failImport = true;
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /native import unavailable/);
  f.controls.failImport = false;
  await refreshCatalog(f, '2026-10-12T09:01:00Z', '2026-10-12T10:01:00Z'); f.controls.currentTime = '2026-10-12T09:02:00Z';
  const recovered = await f.api.act('prepare', { id: board.id });
  assert.equal(recovered.id, board.id); assert.equal(recovered.tasks.filter(t => t.dispatchable).length, 2);
  assert.equal((await readdir(path.join(f.rootFor(board.id), 'flow/catalogs'))).length, 3, 'failed candidates remain evidence without becoming a permanent selected catalog');
}));

test('catalog freshness: delayed dependent work uses renewed health and retains the earlier attempt catalog', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  for (const taskId of ['research', 'design']) { await f.api.act('dispatch', { id: board.id, taskId }); await f.accept(board.id, taskId); }
  const prior = await f.api.state(board.id), researchId = prior.tasks.find(t => t.task_id === 'research').request_id;
  const priorFile = path.join(f.rootFor(board.id), 'runtime/catalogs', `${researchId}.json`);
  const original = await readFile(priorFile, 'utf8');
  f.controls.currentTime = '2026-10-12T11:05:00Z';
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /does not validate/);
  const fresh = await refreshCatalog(f);
  const current = await f.api.act('prepare', { id: board.id });
  assert.equal(current.execution_digest, board.execution_digest);
  const write = current.tasks.find(t => t.task_id === 'write'); assert.equal(write.dispatchable, true);
  assert.equal(await readFile(priorFile, 'utf8'), original);
  const newRecord = JSON.parse(await readFile(path.join(f.rootFor(board.id), 'runtime/catalogs', `${write.request_id}.json`), 'utf8'));
  assert.equal(newRecord.catalog_digest, sha(json(fresh))); assert.notEqual(newRecord.catalog_digest, JSON.parse(original).catalog_digest);
  assert.equal(newRecord.evaluated_at, f.controls.currentTime);
  await f.api.act('dispatch', { id: board.id, taskId: 'write' }); assert.equal(f.submits.length, 3);
}));

test('catalog refresh cannot change selected operation authority and cannot overwrite original invocation evidence', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  f.controls.remoteStatus = 'unknown'; await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  const invocationRef = path.join(f.rootFor(board.id), 'runtime/research/invocation.json'), original = await readFile(invocationRef, 'utf8');
  const originalCatalog = JSON.parse(await readFile(path.join(f.rootFor(board.id), 'runtime/research/invocation-catalog.json'), 'utf8'));
  const changed = await refreshCatalog(f); changed.operations[0].authority = 'external-effect'; await f.put(f.settings.catalog_file, changed);
  f.controls.currentTime = '2026-10-12T11:05:00Z';
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /does not validate/);
  changed.operations[0].authority = 'workspace-mutation'; await f.put(f.settings.catalog_file, changed);
  await f.api.act('prepare', { id: board.id });
  f.controls.remoteStatus = 'succeeded';
  const reconciled = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(reconciled.tasks[0].status, 'review'); assert.equal(f.submits.length, 1);
  assert.equal(await readFile(invocationRef, 'utf8'), original);
  assert.equal(sha(await readFile(path.join(f.rootFor(board.id), 'flow/capability-catalog.json'))), originalCatalog.catalog_digest);
}));

test('interrupted native preparation retains the exact historical catalog when recovery sees refreshed health', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); f.controls.failAfterPrepare = true;
  const original = JSON.parse(await readFile(f.settings.catalog_file, 'utf8'));
  await assert.rejects(() => f.api.act('prepare', { id: board.id }), /interrupted after native preparation/);
  await refreshCatalog(f); f.controls.currentTime = '2026-10-12T11:05:00Z'; f.controls.failAfterPrepare = false;
  const current = await f.api.act('prepare', { id: board.id });
  for (const task of current.tasks.filter(t => t.request_id)) {
    const record = JSON.parse(await readFile(path.join(f.rootFor(board.id), 'runtime/catalogs', `${task.request_id}.json`), 'utf8'));
    assert.equal(record.catalog_digest, sha(json(original))); assert.equal(record.evaluated_at, timestamp);
  }
}));

test('interrupted first dispatch requires current health before its first submit and can refresh a definitely unsent packet', () => fixture(async f => {
  const board = await f.create(); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  f.controls.factoryError = true;
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'research' }), /configuration rejected/);
  const invocationFile = path.join(f.rootFor(board.id), 'runtime/research/invocation.json');
  const original = JSON.parse(await readFile(invocationFile, 'utf8'));
  const journalFile = path.join(f.rootFor(board.id), 'runtime/research/journal.json');
  await assert.rejects(() => readFile(journalFile), /ENOENT/);
  f.controls.currentTime = '2026-10-12T11:05:00Z'; f.controls.factoryError = false;
  const validationsBefore = f.calls.filter(c => c === 'validate-work-graph-capabilities').length;
  const blocked = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(blocked.dispatch.status, 'blocked'); assert.match(blocked.dispatch.blocker, /does not validate/);
  assert.equal(f.submits.length, 0, 'expired saved health never permits a first submit');
  assert.ok(f.calls.filter(c => c === 'validate-work-graph-capabilities').length > validationsBefore);
  assert.equal(JSON.parse(await readFile(journalFile, 'utf8')).phase, 'prepared', 'known unsent work is not labelled unknown');
  const fresh = await refreshCatalog(f);
  const recovered = await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(recovered.dispatch.status, 'succeeded'); assert.equal(f.submits.length, 1);
  assert.equal(f.submittedInvocations[0].evaluated_at, f.controls.currentTime);
  assert.deepEqual(f.submittedInvocations[0].request, original.request, 'freshness never changes attempt/idempotency/payload');
  const current = JSON.parse(await readFile(invocationFile, 'utf8'));
  assert.equal(current.evaluated_at, f.controls.currentTime);
  const record = JSON.parse(await readFile(path.join(f.rootFor(board.id), 'runtime/research/invocation-catalog.json'), 'utf8'));
  assert.equal(record.catalog_digest, sha(json(fresh)));
  assert.equal((await readdir(path.join(f.rootFor(board.id), 'runtime/research/invocations'))).length, 2, 'the earlier unsent snapshot remains inspectable');
}));

function capacityPlan() {
  const value = plan();
  value.tasks[1].owner_id = 'owner-a';
  return value;
}

test('owner capacity creates review-bound dependency lanes without changing authored plan or acceptance', () => {
  const original = make(capacityPlan()), before = json(original);
  const child = proposeCapacity({ handoff: original, ownerLimits: { 'owner-a': 1 }, recordedAt: timestamp });
  assert.notEqual(child.id, original.id);
  assert.equal(json(original), before);
  assert.equal(child.source.plan_digest, original.source.plan_digest);
  assert.equal(child.source.capacity.parent_execution_digest, original.execution_digest);
  assert.deepEqual(child.graph.items[1].depends_on, ['research']);
  assert.deepEqual(child.graph.items[2].depends_on, ['research', 'design']);
  for (const task of child.source.tasks) {
    const prior = original.source.tasks.find(t => t.task_id === task.task_id);
    assert.deepEqual(task.acceptance_criteria, prior.acceptance_criteria);
    assert.deepEqual(task.required_evidence, prior.required_evidence);
    assert.equal(task.owner_id, prior.owner_id);
  }
  assert.throws(() => verifyApproval(child, reviewFor(original)), /exact named/);
  assert.equal(proposeCapacity({ handoff: original, ownerLimits: { 'owner-a': 1 }, recordedAt: timestamp }).id, child.id);
  assert.throws(() => proposeCapacity({ handoff: child, ownerLimits: { 'owner-a': 1 }, recordedAt: timestamp }), /existing capacity or rework/);
});

test('capacity lanes respect topological order even when source tasks are reversed', () => {
  const value = capacityPlan(); value.tasks.reverse();
  const child = proposeCapacity({ handoff: make(value), ownerLimits: { 'owner-a': 1 }, recordedAt: timestamp });
  assert.deepEqual(child.source.capacity.assignments.map(a => a.task_id), ['research', 'design', 'write']);
  assert.deepEqual(child.graph.items.find(i => i.work_item_id === 'design').depends_on, ['research']);
  for (const invalid of [null, [], {}, { 'owner-a': 0 }, { 'owner-a': 1.1 }, { 'owner-a': '1' }, { 'owner-a': 101 }, { 'owner-a': 1, outsider: 1 }]) {
    assert.throws(() => proposeCapacity({ handoff: make(value), ownerLimits: invalid, recordedAt: timestamp }), /one integer capacity/);
  }
  assert.throws(() => proposeCapacity({ handoff: make(value), ownerLimits: { 'owner-a': 100 }, recordedAt: timestamp }), /no dependency edges/);
});

test('capacity scopes are durable, idempotent, leave original untouched and cannot rescope imported work', async () => {
  await fixture(async ctx => {
    const original = await ctx.api.act('create', { planText: json(capacityPlan()), outcome: 'Capacity-limited brief', workspaceRoot: ctx.directory, modelSelector: ctx.settings.model_selector });
    const child = await ctx.api.act('capacity', { id: original.id, ownerLimits: { 'owner-a': 1 } });
    assert.equal(child.status, 'awaiting_import');
    assert.deepEqual(child.graph.items[1].depends_on, ['research']);
    assert.equal((await ctx.api.act('capacity', { id: original.id, ownerLimits: { 'owner-a': 1 } })).id, child.id);
    assert.deepEqual((await ctx.api.state(original.id)).graph.items[1].depends_on, []);
    assert.equal(ctx.calls.length, 0); assert.equal(ctx.submits.length, 0);
    const saved = await readFile(path.join(ctx.rootFor(child.id), 'source-plan.json'), 'utf8');
    assert.equal(saved, json(capacityPlan()));
    await ctx.approve(child.id);
    await ctx.api.act('prepare', { id: child.id });
    const projection = await ctx.readProjection(child.id);
    assert.equal(projection.items.find(i => i.work_item_id === 'research').status, 'active');
    assert.equal(projection.items.find(i => i.work_item_id === 'design').status, 'ready');
    await assert.rejects(() => ctx.api.act('capacity', { id: child.id, ownerLimits: { 'owner-a': 2 } }), /unimported board/);
  });
});

test('capacity UI shows proposal controls and exact added edges with escaped owner labels', () => {
  const handoff = make(capacityPlan()), projected = { ...projectDeliverable(handoff, null), source: handoff.source, graph: handoff.graph };
  let html = renderDeliverablePanel({ entries: [projected], selected: projected.id, draft: {}, busy: false });
  assert.match(html, /Create capacity-scoped board/); assert.match(html, /owner-a/);
  const child = proposeCapacity({ handoff, ownerLimits: { 'owner-a': 1 }, recordedAt: timestamp });
  html = renderDeliverablePanel({ entries: [{ ...projectDeliverable(child, null), source: child.source, graph: child.graph }], selected: child.id, draft: {}, busy: false });
  assert.match(html, /Owner capacities: owner-a: 1/); assert.match(html, /design waits for research/); assert.doesNotMatch(html, /data-action="capacity"/);
});

const specialistSpecs = () => [
  { task_id: 'facts', name: 'Fact-check contribution', owner_id: 'owner-a', acceptance_criteria: ['Verify the source claims'], required_evidence: ['Checked source notes'] },
  { task_id: 'alternatives', name: 'Alternative analysis', owner_id: 'owner-b', acceptance_criteria: ['Compare two alternatives'], required_evidence: ['Comparison text'] },
];
test('specialists fan out after prerequisites and retain original integration and downstream acceptance', () => {
  const original = make(), before = json(original);
  const child = proposeSpecialists({ handoff: original, taskId: 'write', specialists: specialistSpecs(), recordedAt: timestamp });
  assert.equal(json(original), before);
  assert.deepEqual(child.source.tasks.find(t => t.task_id === 'facts').dependencies, ['research', 'design']);
  assert.deepEqual(child.source.tasks.find(t => t.task_id === 'write'), { ...original.source.tasks[2], dependencies: ['research', 'design', 'facts', 'alternatives'] });
  assert.equal(child.source.plan_digest, original.source.plan_digest);
  assert.notEqual(child.execution_digest, original.execution_digest);
  assert.throws(() => verifyApproval(child, reviewFor(original)), /exact named/);
  assert.match(child.requests['inputs/write.json'].objective, /Integrate the independently reviewed/);
  assert.deepEqual(child.requests['inputs/facts.json'].criteria, [{ id: 'criterion-1', criterion: 'Verify the source claims' }]);
  const first = proposeSpecialists({ handoff: original, taskId: 'research', specialists: specialistSpecs(), recordedAt: timestamp });
  assert.deepEqual(first.source.tasks.find(t => t.task_id === 'write').dependencies, ['research', 'design']);
  assert.throws(() => proposeCapacity({ handoff: child, ownerLimits: { 'owner-a': 1, 'owner-b': 1 }, recordedAt: timestamp }), /no dependency edges/);
  assert.throws(() => proposeSpecialists({ handoff: child, taskId: 'write', specialists: specialistSpecs(), recordedAt: timestamp }), /original unstarted/);
});
test('specialist proposals reject unsafe, ambiguous, missing and authority-expanding fields', () => {
  const args = { handoff: make(), taskId: 'write', recordedAt: timestamp };
  for (const edit of [s => s.pop(), s => { s[0].task_id = 'write'; }, s => { s[1].task_id = s[0].task_id; }, s => { s[0].task_id = '../escape'; }, s => { s[0].owner_id = 'unknown'; }, s => { s[0].acceptance_criteria = []; }, s => { s[0].required_evidence = ['']; }, s => { s[0].name = ''; }, s => { s[0].dependencies = []; }, s => { s[0].provider_calls_approved = true; }]) {
    const specs = specialistSpecs(); edit(specs); assert.throws(() => proposeSpecialists({ ...args, specialists: specs }));
  }
  for (const specs of [null, {}, Array(11).fill(specialistSpecs()[0])]) assert.throws(() => proposeSpecialists({ ...args, specialists: specs }));
  assert.throws(() => proposeSpecialists({ ...args, taskId: 'missing', specialists: specialistSpecs() }));
});
test('specialist workflow completes contributions before integration, preserving review and dispatch boundaries', () => fixture(async f => {
  const original = await f.create(), originalHandoff = await f.getHandoff(original.id);
  const payload = { id: original.id, taskId: 'write', specialists: specialistSpecs() };
  const child = await f.api.act('specialists', payload);
  assert.equal(child.status, 'awaiting_import'); assert.equal(f.calls.length, 0);
  f.controls.currentTime = '2026-10-12T09:00:01Z';
  assert.equal((await f.api.act('specialists', payload)).id, child.id);
  assert.equal(await readFile(path.join(f.rootFor(child.id), 'source-plan.json'), 'utf8'), json(plan()));
  assert.deepEqual(await f.getHandoff(original.id), originalHandoff);
  await f.approve(original.id, true);
  await assert.rejects(() => f.api.act('prepare', { id: child.id }), /exact named/);
  await f.approve(child.id, true);
  let state = await f.api.act('prepare', { id: child.id });
  assert.deepEqual(state.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['research', 'design']);
  await assert.rejects(() => f.api.act('specialists', { ...payload, id: child.id }), /unimported/);
  for (const taskId of ['research', 'design']) { await f.api.act('dispatch', { id: child.id, taskId }); await f.accept(child.id, taskId); }
  state = await f.api.act('prepare', { id: child.id });
  assert.deepEqual(state.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['facts', 'alternatives']);
  for (const taskId of ['facts', 'alternatives']) await f.api.act('dispatch', { id: child.id, taskId });
  state = await f.api.act('prepare', { id: child.id });
  assert.equal(state.tasks.find(t => t.task_id === 'write').dispatchable, false);
  await f.accept(child.id, 'facts');
  state = await f.api.act('prepare', { id: child.id }); assert.equal(state.tasks.find(t => t.task_id === 'write').dispatchable, false);
  await f.accept(child.id, 'alternatives');
  state = await f.api.act('prepare', { id: child.id }); assert.equal(state.tasks.find(t => t.task_id === 'write').dispatchable, true);
  await f.api.act('dispatch', { id: child.id, taskId: 'write' }); await f.accept(child.id, 'write');
  const integration = f.submittedInvocations.find(i => i.request.work_item_id === 'write');
  assert.ok(integration.request.input_artifacts.includes('reviews/facts.json'));
  assert.ok(integration.request.input_artifacts.includes('reviews/alternatives.json'));
  const result = await f.api.act('assemble', { id: child.id });
  assert.equal(result.assembly.entries.length, 5); assert.equal(result.assembly.customer_accepted, false);
  assert.match(result.text, /Fact-check contribution/);
  assert.equal((await f.api.state(original.id)).status, 'awaiting_import');
}));
test('specialist UI exposes contribution scope and escapes retained provenance', () => {
  const handoff = make();
  let entry = { ...projectDeliverable(handoff, null), source: handoff.source, graph: handoff.graph };
  let html = renderDeliverablePanel({ entries: [entry], selected: entry.id, draft: { specialistRows: [{ task_id: 'part', name: '<script>', owner_id: 'owner-a', criteria: '', evidence: '' }] }, busy: false });
  assert.match(html, /Create specialist delegation/); assert.match(html, /&lt;script&gt;/);
  const child = proposeSpecialists({ handoff, taskId: 'write', specialists: specialistSpecs(), recordedAt: timestamp });
  entry = { ...projectDeliverable(child, null), source: child.source, graph: child.graph };
  html = renderDeliverablePanel({ entries: [entry], selected: entry.id, draft: {}, busy: false });
  assert.match(html, /Original integration gate: write/); assert.match(html, /Contributions: facts, alternatives/);
  assert.doesNotMatch(html, /data-action="specialists"/);
  assert.match(html, /data-action="capacity"/);
});
function panelHarness() {
  const nodes = new Map();
  const node = (key, dataset = {}) => { if (!nodes.has(key)) nodes.set(key, { dataset, value: '', events: {}, addEventListener(type, listener) { this.events[type] = listener; } }); return nodes.get(key); };
  const fields = [0, 1].flatMap(index => ['name', 'owner_id', 'criteria', 'evidence'].map(field => node(`${index}-${field}`, { specialistRow: String(index), specialistField: field })));
  const integration = node('integration'), saved = node('saved'), submit = node('submit', { action: 'specialists' }), add = node('add', { action: 'specialist-add' }), remove = node('remove', { action: 'specialist-remove', row: '2' });
  const host = { innerHTML: '', querySelectorAll(selector) { return selector === '[data-specialist-field]' ? fields : selector === '[data-action]' ? [submit, add, remove] : []; }, querySelector(selector) { return selector === '[data-specialist-task]' ? integration : selector === '[data-select]' ? saved : null; } };
  const input = (index, field, value) => { const n = node(`${index}-${field}`); n.value = value; n.events[field === 'owner_id' ? 'change' : 'input']({ target: n }); };
  const fill = () => { for (let index = 0; index < 2; index++) { input(index, 'name', `Contribution ${index + 1}`); input(index, 'owner_id', index ? 'owner-b' : 'owner-a'); input(index, 'criteria', 'Verify source claims\nCheck alternatives'); input(index, 'evidence', 'Source notes'); } };
  return { host, integration, saved, submit, add, remove, input, fill };
}
test('mounted specialist form validates, adds/removes rows, submits selected integration and resets stale selection', () => fixture(async f => {
  const original = await f.create(), h = panelHarness(), requests = [];
  const dispose = mountDeliverablePanel(h.host, { fetcher: async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await f.api.list() }) };
    const payload = JSON.parse(options.body); requests.push({ url, payload });
    return { ok: true, json: async () => f.api.act(url.split('/').at(-1), payload) };
  } });
  await new Promise(resolve => setTimeout(resolve, 10));
  h.integration.value = 'write'; h.integration.events.change({ target: h.integration });
  await h.submit.events.click(); assert.equal(requests.length, 0); assert.match(h.host.innerHTML, /Every contribution needs/);
  h.fill(); await h.add.events.click(); assert.match(h.host.innerHTML, /Contribution 3/);
  await h.remove.events.click(); assert.doesNotMatch(h.host.innerHTML, /Contribution 3/);
  await h.submit.events.click();
  assert.equal(requests.length, 1); assert.equal(requests[0].url, '/api/deliverables/specialists');
  assert.equal(requests[0].payload.id, original.id); assert.equal(requests[0].payload.taskId, 'write');
  assert.deepEqual(requests[0].payload.specialists[0].acceptance_criteria, ['Verify source claims', 'Check alternatives']);
  assert.match(h.host.innerHTML, /Original integration gate: write/);
  h.saved.value = original.id; h.saved.events.change({ target: h.saved });
  assert.doesNotMatch(h.host.innerHTML, /value="Contribution 1"/);
  await h.submit.events.click(); assert.equal(requests.length, 1, 'switching board clears stale form contents'); dispose();
}));
test('specialist mounted repeated clicks serialize and late results cannot redraw a dismissed panel', () => fixture(async f => {
  await f.create(); const h = panelHarness(); let release, writes = 0;
  const pending = new Promise(resolve => { release = resolve; });
  const dispose = mountDeliverablePanel(h.host, { fetcher: async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await f.api.list() }) };
    writes++; await pending;
    return { ok: true, json: async () => f.api.act('specialists', JSON.parse(options.body)) };
  } });
  await new Promise(resolve => setTimeout(resolve, 10)); h.fill(); h.integration.value = 'write';
  const first = h.submit.events.click(); await h.submit.events.click(); assert.equal(writes, 1);
  const before = h.host.innerHTML; dispose(); release(); await first;
  assert.equal(h.host.innerHTML, before); assert.equal((await f.api.list()).length, 2);
}));
test('generated specialist IDs avoid existing task collisions and form owners come from the board', () => {
  const rows = specialistRows({ tasks: [{ task_id: 'specialist-1', owner_id: 'alpha' }, { task_id: 'specialist-3', owner_id: 'beta' }] });
  assert.deepEqual(rows.map(r => r.task_id), ['specialist-2', 'specialist-4']);
  assert.deepEqual(rows.map(r => r.owner_id), ['alpha', 'beta']);
});

const sameOwnerSpecs = () => specialistSpecs().map(spec => ({ ...spec, owner_id: 'owner-a' }));
test('R592 capacity composes specialist provenance and preserves the exact integration gate', () => {
  const original = make(), delegated = proposeSpecialists({ handoff: original, taskId: 'write', specialists: sameOwnerSpecs(), recordedAt: timestamp });
  const before = json(delegated);
  const child = proposeCapacity({ handoff: delegated, ownerLimits: { 'owner-a': 1, 'owner-b': 1 }, recordedAt: timestamp });
  assert.equal(json(delegated), before);
  assert.deepEqual(child.source.specialists, delegated.source.specialists);
  assert.equal(child.source.capacity.parent_id, delegated.id);
  assert.equal(child.source.capacity.parent_execution_digest, delegated.execution_digest);
  assert.equal(child.source.specialists.parent_id, original.id);
  assert.equal(child.source.plan_digest, original.source.plan_digest);
  assert.deepEqual(child.source.capacity.added_dependencies, [{ task_id: 'alternatives', prerequisite_id: 'facts', owner_id: 'owner-a', lane: 1 }]);
  assert.deepEqual(child.source.capacity.original_dependencies, delegated.source.tasks.map(t => ({ task_id: t.task_id, dependencies: t.dependencies })));
  for (const task of delegated.source.tasks) {
    const scoped = child.source.tasks.find(t => t.task_id === task.task_id);
    assert.deepEqual({ ...scoped, dependencies: task.dependencies }, task, 'only prerequisites may change');
    assert.ok(task.dependencies.every(id => scoped.dependencies.includes(id)));
  }
  assert.deepEqual(child.source.tasks.find(t => t.task_id === 'write'), delegated.source.tasks.find(t => t.task_id === 'write'));
  assert.match(child.requests['inputs/write.json'].objective, /Integrate the independently reviewed specialist contributions/);
  assert.deepEqual(child.requests['inputs/write.json'].criteria, delegated.requests['inputs/write.json'].criteria);
  for (const prior of [original, delegated]) assert.throws(() => verifyApproval(child, reviewFor(prior)), /exact named/);
  assert.equal(verifyApproval(child, reviewFor(child)).provider_calls_approved, false);
  assert.throws(() => verifyApproval(child, reviewFor(child), true), /explicit approval/);
  assert.equal(projectDeliverable(child, null).status, 'awaiting_import');
  assert.ok(projectDeliverable(child, null).tasks.every(t => !t.dispatchable));
});

test('R592 lane bounds hold for all reachable acceptance frontiers with mixed owners and reversed tasks', () => {
  for (const reverse of [false, true]) for (const a of [1, 2]) for (const b of [1, 2]) {
    const value = plan(); if (reverse) value.tasks.reverse();
    const original = make(value);
    const specs = ['facts', 'alternatives', 'evidence', 'critique', 'summary'].map((id, i) => ({
      task_id: id, name: id, owner_id: i < 3 ? 'owner-a' : 'owner-b', acceptance_criteria: [`Review ${id}`], required_evidence: [`${id} notes`],
    }));
    const delegated = proposeSpecialists({ handoff: original, taskId: 'write', specialists: specs, recordedAt: timestamp });
    const limits = { 'owner-a': a, 'owner-b': b };
    const scoped = proposeCapacity({ handoff: delegated, ownerLimits: limits, recordedAt: timestamp });
    const tasks = scoped.source.tasks, order = scoped.source.capacity.assignments.map(t => t.task_id);
    for (const task of tasks) assert.ok(task.dependencies.every(dep => order.indexOf(dep) < order.indexOf(task.task_id)), 'lanes never create a cycle');
    for (let mask = 0; mask < 2 ** tasks.length; mask++) {
      const accepted = new Set(tasks.filter((_, i) => mask & (1 << i)).map(t => t.task_id));
      if (tasks.some(t => accepted.has(t.task_id) && t.dependencies.some(dep => !accepted.has(dep)))) continue;
      const ready = tasks.filter(t => !accepted.has(t.task_id) && t.dependencies.every(dep => accepted.has(dep)));
      for (const [owner, limit] of Object.entries(limits)) assert.ok(ready.filter(t => t.owner_id === owner).length <= limit);
    }
    assert.deepEqual(tasks.find(t => t.task_id === 'write').acceptance_criteria, original.source.tasks.find(t => t.task_id === 'write').acceptance_criteria);
    assert.ok(delegated.source.specialists.contribution_ids.every(id => tasks.find(t => t.task_id === 'write').dependencies.includes(id)));
    const parallel = tasks.filter(t => ['facts', 'critique'].includes(t.task_id));
    assert.ok(parallel.every(t => !t.dependencies.some(id => ['facts', 'critique'].includes(id))), 'separate owners retain parallel first contributions');
  }
});

test('R592 delegated capacity rejects malformed, no-op, repeated-scoping and reverse composition', () => {
  const delegated = proposeSpecialists({ handoff: make(), taskId: 'write', specialists: sameOwnerSpecs(), recordedAt: timestamp });
  const before = json(delegated);
  for (const ownerLimits of [null, [], {}, { 'owner-a': 1 }, { 'owner-a': 1, 'owner-b': 0 }, { 'owner-a': 1.5, 'owner-b': 1 }, { 'owner-a': '1', 'owner-b': 1 }, { 'owner-a': 101, 'owner-b': 1 }, { 'owner-a': 1, 'owner-b': 1, outsider: 1 }]) {
    assert.throws(() => proposeCapacity({ handoff: delegated, ownerLimits, recordedAt: timestamp }), /one integer capacity/);
  }
  assert.throws(() => proposeCapacity({ handoff: delegated, ownerLimits: { 'owner-a': 100, 'owner-b': 100 }, recordedAt: timestamp }), /no dependency edges/);
  const child = proposeCapacity({ handoff: delegated, ownerLimits: { 'owner-a': 1, 'owner-b': 1 }, recordedAt: timestamp });
  assert.throws(() => proposeCapacity({ handoff: child, ownerLimits: { 'owner-a': 2, 'owner-b': 1 }, recordedAt: timestamp }), /existing capacity or rework/);
  assert.throws(() => proposeSpecialists({ handoff: child, taskId: 'write', specialists: sameOwnerSpecs(), recordedAt: timestamp }), /original unstarted/);
  assert.equal(json(delegated), before);
});

test('R592 real host keeps contribution lane and integration review gates through the synthetic execution journey', () => fixture(async f => {
  const original = await f.create();
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const before = await f.getHandoff(delegated.id), payload = { id: delegated.id, ownerLimits: { 'owner-a': 1, 'owner-b': 1 } };
  const child = await f.api.act('capacity', payload);
  f.controls.currentTime = '2026-10-12T09:00:01Z';
  assert.equal((await f.api.act('capacity', payload)).id, child.id);
  assert.deepEqual(await f.getHandoff(delegated.id), before);
  assert.equal(await readFile(path.join(f.rootFor(child.id), 'source-plan.json'), 'utf8'), json(plan()));
  assert.equal(child.status, 'awaiting_import'); assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
  await f.approve(delegated.id, true);
  await assert.rejects(() => f.api.act('prepare', { id: child.id }), /exact named/);
  await f.approve(child.id, true);
  let state = await f.api.act('prepare', { id: child.id });
  assert.deepEqual(state.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['research', 'design']);
  for (const taskId of ['research', 'design']) { await f.api.act('dispatch', { id: child.id, taskId }); await f.accept(child.id, taskId); }
  state = await f.api.act('prepare', { id: child.id });
  assert.deepEqual(state.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['facts']);
  await f.api.act('dispatch', { id: child.id, taskId: 'facts' });
  state = await f.api.act('prepare', { id: child.id });
  assert.equal(state.tasks.find(t => t.task_id === 'alternatives').dispatchable, false, 'execution without acceptance never releases a lane');
  await f.accept(child.id, 'facts');
  state = await f.api.act('prepare', { id: child.id });
  assert.deepEqual(state.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['alternatives']);
  assert.equal(state.tasks.find(t => t.task_id === 'write').dispatchable, false);
  await f.api.act('dispatch', { id: child.id, taskId: 'alternatives' });
  state = await f.api.act('prepare', { id: child.id });
  assert.equal(state.tasks.find(t => t.task_id === 'write').dispatchable, false, 'all contributions still need named review');
  await f.accept(child.id, 'alternatives');
  state = await f.api.act('prepare', { id: child.id });
  assert.deepEqual(state.tasks.filter(t => t.dispatchable).map(t => t.task_id), ['write']);
  await f.api.act('dispatch', { id: child.id, taskId: 'write' }); await f.accept(child.id, 'write');
  const integration = f.submittedInvocations.find(i => i.request.work_item_id === 'write');
  assert.ok(integration.request.input_artifacts.includes('reviews/facts.json'));
  assert.ok(integration.request.input_artifacts.includes('reviews/alternatives.json'));
  const assembly = await f.api.act('assemble', { id: child.id });
  assert.equal(assembly.assembly.entries.length, 5); assert.equal(assembly.assembly.customer_accepted, false);
  assert.equal((await f.api.state(original.id)).status, 'awaiting_import');
  assert.equal((await f.api.state(delegated.id)).status, 'awaiting_import');
  await f.approve(delegated.id); await f.api.act('prepare', { id: delegated.id });
  await assert.rejects(() => f.api.act('capacity', payload), /unimported board/);
}));

test('R592 corrupted delegated source blocks capacity without producing a new child', () => fixture(async f => {
  const original = await f.create();
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const before = await f.getHandoff(delegated.id);
  await f.put(path.join(f.rootFor(delegated.id), 'source-plan.json'), 'changed plan bytes');
  await assert.rejects(() => f.api.act('capacity', { id: delegated.id, ownerLimits: { 'owner-a': 1, 'owner-b': 1 } }), /Source plan bytes changed/);
  assert.equal((await f.api.list()).length, 2);
  assert.deepEqual(await f.getHandoff(delegated.id), before);
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
}));

// Minimal event-capable host: controls are discovered from the actual rendered
// production panel. This executes input/change/click handlers, not a browser.
function capacityPanelHarness() {
  let html = '', controls = {};
  const unescape = text => text.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const node = (dataset, value = '') => ({ dataset, value, events: {}, addEventListener(type, handler) { this.events[type] = handler; } });
  const host = {
    get innerHTML() { return html; },
    set innerHTML(value) {
      html = value; controls = {};
      if (html.includes('data-select')) controls.saved = node({});
      const field = html.match(/<textarea data-field="ownerLimits"[^>]*>([\s\S]*?)<\/textarea>/);
      if (field) controls.limits = node({ field: 'ownerLimits' }, unescape(field[1]));
      if (html.includes('data-action="capacity"')) controls.capacity = node({ action: 'capacity' });
    },
    querySelectorAll(selector) { return selector === '[data-field]' ? [controls.limits].filter(Boolean) : selector === '[data-action]' ? [controls.capacity].filter(Boolean) : []; },
    querySelector(selector) { return selector === '[data-select]' ? controls.saved : selector === '[data-field="ownerLimits"]' ? controls.limits : null; },
  };
  return { host, get controls() { return controls; }, select(id) { controls.saved.value = id; controls.saved.events.change({ target: controls.saved }); }, input(value) { controls.limits.value = value; controls.limits.events.input({ target: controls.limits }); } };
}

test('R592 mounted delegated capacity validates, submits, retains provenance and resets board-local limits', () => fixture(async f => {
  const original = await f.create();
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const h = capacityPanelHarness(), requests = [];
  const dispose = mountDeliverablePanel(h.host, { fetcher: async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await f.api.list() }) };
    const payload = JSON.parse(options.body); requests.push({ url, payload });
    try { const result = await f.api.act(url.split('/').at(-1), payload); return { ok: true, json: async () => result }; }
    catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
  } });
  await new Promise(resolve => setTimeout(resolve, 10)); h.select(delegated.id);
  assert.match(h.host.innerHTML, /Includes every specialist contribution/);
  h.input('{'); await h.controls.capacity.events.click();
  assert.match(h.host.innerHTML, /Owner capacities must be a JSON object/); assert.equal(requests.length, 0);
  h.input('{"owner-a":0,"owner-b":1}'); await h.controls.capacity.events.click();
  assert.match(h.host.innerHTML, /one integer capacity/); assert.equal((await f.api.list()).length, 2);
  h.input('{"owner-a":1,"owner-b":1}'); await h.controls.capacity.events.click();
  assert.equal(requests.at(-1).url, '/api/deliverables/capacity'); assert.equal(requests.at(-1).payload.id, delegated.id);
  assert.deepEqual(requests.at(-1).payload.ownerLimits, { 'owner-a': 1, 'owner-b': 1 });
  assert.match(h.host.innerHTML, /alternatives waits for facts/); assert.match(h.host.innerHTML, /Original integration gate: write/);
  assert.match(h.host.innerHTML, /Nothing has executed/); assert.equal(h.controls.capacity, undefined);
  h.select(delegated.id); h.input('{"owner-a":99,"owner-b":1}'); h.select(original.id);
  assert.equal(h.controls.limits.value, '{"owner-a":1,"owner-b":1}', 'saved-board change discards another board\'s limits');
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []); dispose();
}));

test('R592 mounted capacity serializes repeated clicks and ignores a late result after disposal', () => fixture(async f => {
  const original = await f.create();
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const h = capacityPanelHarness(); let release, writes = 0;
  const pending = new Promise(resolve => { release = resolve; });
  const dispose = mountDeliverablePanel(h.host, { fetcher: async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await f.api.list() }) };
    writes++; await pending;
    return { ok: true, json: async () => f.api.act('capacity', JSON.parse(options.body)) };
  } });
  await new Promise(resolve => setTimeout(resolve, 10)); h.select(delegated.id);
  const first = h.controls.capacity.events.click(); await h.controls.capacity.events.click(); assert.equal(writes, 1);
  const before = h.host.innerHTML; dispose(); release(); await first;
  assert.equal(h.host.innerHTML, before); assert.equal((await f.api.list()).length, 3);
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
}));

test('R592 detached capacity input cannot overwrite the newly selected board capacity', () => fixture(async f => {
  const original = await f.create();
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const h = capacityPanelHarness(), requests = [];
  const dispose = mountDeliverablePanel(h.host, { fetcher: async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await f.api.list() }) };
    requests.push(JSON.parse(options.body));
    return { ok: false, json: async () => ({ error: 'Read-only test observer; request not applied' }) };
  } });
  await new Promise(resolve => setTimeout(resolve, 10)); h.select(delegated.id);
  const staleInput = h.controls.limits; staleInput.value = '{"owner-a":2,"owner-b":2}';
  h.select(original.id); staleInput.events.input({ target: staleInput });
  assert.equal(h.controls.limits.value, '{"owner-a":1,"owner-b":1}');
  await h.controls.capacity.events.click();
  assert.equal(requests[0].id, original.id);
  assert.deepEqual(requests[0].ownerLimits, { 'owner-a': 1, 'owner-b': 1 });
  dispose();
}));

test('R592 detached capacity button and selector cannot retarget a newly selected board', () => fixture(async f => {
  const original = await f.create();
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const h = capacityPanelHarness(), requests = [];
  const dispose = mountDeliverablePanel(h.host, { fetcher: async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await f.api.list() }) };
    requests.push(JSON.parse(options.body));
    return { ok: false, json: async () => ({ error: 'Read-only test observer; request not applied' }) };
  } });
  await new Promise(resolve => setTimeout(resolve, 10)); h.select(delegated.id);
  const staleButton = h.controls.capacity, staleSelector = h.controls.saved;
  h.select(original.id); staleSelector.value = delegated.id; staleSelector.events.change({ target: staleSelector });
  await staleButton.events.click(); assert.equal(requests.length, 0);
  await h.controls.capacity.events.click(); assert.equal(requests[0].id, original.id);
  dispose();
}));

const localEvidence = (task_ids = ['research'], text = '\uFEFF# Source\r\n雪,original bytes\r\n') => ({ name: 'source.md', task_ids, content_base64: Buffer.from(text).toString('base64') });
const evidencePayload = (directory, evidenceFiles = [localEvidence()]) => ({ planText: json(plan()), outcome: 'A reviewed launch brief', workspaceRoot: directory, modelSelector: 'moongate/approved-model', evidenceFiles });
async function createEvidence(f, files = [localEvidence()]) {
  const payload = evidencePayload(f.directory, files), preview = await f.api.act('preview', payload);
  return f.api.act('create', { ...payload, previewDigest: preview.execution_digest });
}

test('R606 evidence binds original bytes and exact task assignments without broadening authority', () => {
  const options = { ...evidencePayload('/tmp/approved'), recordedAt: timestamp, artifactRoot: '/tmp/approved/data/deliverables' };
  const handoff = compileDeliverable(options), file = handoff.source.local_evidence.files[0];
  assert.equal(file.digest, sha(Buffer.from(options.evidenceFiles[0].content_base64, 'base64')));
  assert.deepEqual(file.task_ids, ['research']);
  assert.ok(handoff.graph.items[0].input_artifacts.includes(file.artifact_ref));
  assert.ok(handoff.graph.items.slice(1).every(i => !i.input_artifacts.includes(file.artifact_ref)));
  assert.match(handoff.requests['inputs/research.json'].profile.instructions.at(-1), /untrusted source material/);
  assert.match(handoff.requests['inputs/research.json'].profile.instructions.at(-1), new RegExp(file.digest));
  assert.doesNotMatch(handoff.requests['inputs/design.json'].profile.instructions.join('\n'), /local-evidence\//);
  for (const changed of [[localEvidence(['design'])], [localEvidence(['research'], '# Source\n雪,original bytes\n')]]) assert.notEqual(compileDeliverable({ ...options, evidenceFiles: changed }).id, handoff.id);
  assert.equal(compileDeliverable({ ...options, evidenceFiles: [] }).id, make().id);
  assert.equal(compileDeliverable({ ...options, evidenceFiles: undefined }).id, make().id);
});

test('R606 rejects unknown/path/duplicate/unassigned sources, bad encodings, binary and oversize input', () => {
  const opts = { ...evidencePayload('/tmp/approved'), recordedAt: timestamp, artifactRoot: '/tmp/approved/data/deliverables' };
  const good = localEvidence();
  for (const evidenceFiles of [null, {}, [good, good], [{ ...good, path: '/etc/passwd' }], [{ ...good, name: '../source.md' }], [{ ...good, name: 'source.exe' }], [{ ...good, name: 'x\n.md' }], [{ ...good, content_base64: '!!!!' }], [{ ...good, content_base64: 'AB==' }], [{ ...good, content_base64: Buffer.from([0xff]).toString('base64') }], [localEvidence(['research'], '\0binary')], [localEvidence(['missing'])], [localEvidence([])], [localEvidence(['research', 'research'])], [localEvidence(['research'], 'x'.repeat(131073))], Array.from({ length: 3 }, (_, i) => ({ ...localEvidence(['research'], 'x'.repeat(100000)), name: `source-${i}.txt` })), Array.from({ length: 13 }, (_, i) => ({ ...good, name: `${i}.txt` }))]) assert.throws(() => compileDeliverable({ ...opts, evidenceFiles }));
});

test('R606 host preview is read-only, exact save is durable, retries repair missing bytes and tampering fails closed', () => fixture(async f => {
  const payload = evidencePayload(f.directory), preview = await f.api.act('preview', payload);
  assert.equal(preview.preview, true); assert.deepEqual(await f.api.list(), []);
  await assert.rejects(() => f.api.act('create', payload), /Preview/);
  await assert.rejects(() => f.api.act('create', { ...payload, previewDigest: sha('stale') }), /Preview/);
  const board = await f.api.act('create', { ...payload, previewDigest: preview.execution_digest });
  const file = board.source.local_evidence.files[0], target = path.join(f.rootFor(board.id), file.artifact_ref);
  assert.deepEqual(await readFile(target), Buffer.from(payload.evidenceFiles[0].content_base64, 'base64'));
  const inspected = await f.api.act('inspect-evidence', { id: board.id, artifactRef: file.artifact_ref });
  assert.equal(inspected.evidence.text, '\uFEFF# Source\r\n雪,original bytes\r\n');
  await assert.rejects(() => f.api.act('inspect-evidence', { id: board.id, artifactRef: '../../outside.txt' }), /declared/);
  await rm(target); assert.equal((await f.api.list())[0].status, 'verification_blocked');
  assert.equal((await f.api.act('create', { ...payload, previewDigest: preview.execution_digest })).id, board.id);
  assert.deepEqual(await readFile(target), Buffer.from(payload.evidenceFiles[0].content_base64, 'base64'));
  await writeFile(target, 'changed');
  for (const action of ['prepare', 'dispatch', 'inspect-evidence']) await assert.rejects(() => f.api.act(action, { id: board.id, taskId: 'research', artifactRef: file.artifact_ref }), /bytes changed/);
  await assert.rejects(() => f.api.act('create', { ...payload, previewDigest: preview.execution_digest }), /differs/);
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
}));

test('R606 stored evidence symlinks fail before inspection, copying or native operations', () => fixture(async f => {
  const board = await createEvidence(f), file = board.source.local_evidence.files[0];
  const target = path.join(f.rootFor(board.id), file.artifact_ref), outside = path.join(f.directory, 'outside.txt');
  await writeFile(outside, 'outside'); await rm(target); await symlink(outside, target);
  for (const action of ['prepare', 'inspect-evidence', 'capacity']) await assert.rejects(() => f.api.act(action, { id: board.id, artifactRef: file.artifact_ref, ownerLimits: { 'owner-a': 1, 'owner-b': 1 } }), /symlink|no dependency/);
  await assert.rejects(() => createEvidence(f), /regular file/);
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
}));

test('R606 evidence survives specialist/capacity children without assigning new tasks implicitly', () => fixture(async f => {
  const board = await createEvidence(f, [localEvidence(['write'])]);
  const delegated = await f.api.act('specialists', { id: board.id, taskId: 'write', specialists: sameOwnerSpecs() });
  const child = await f.api.act('capacity', { id: delegated.id, ownerLimits: { 'owner-a': 1, 'owner-b': 1 } });
  for (const scope of [board, delegated, child]) {
    assert.deepEqual(scope.source.local_evidence, board.source.local_evidence);
    const file = scope.source.local_evidence.files[0];
    assert.deepEqual(await readFile(path.join(f.rootFor(scope.id), file.artifact_ref)), Buffer.from(localEvidence().content_base64, 'base64'));
    assert.ok(scope.graph.items.filter(i => i.work_item_id !== 'write').every(i => !i.input_artifacts.includes(file.artifact_ref)));
  }
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
}));

test('R606 fixture native preparation declares evidence and refuses changed bytes before dispatch', () => fixture(async f => {
  const board = await createEvidence(f); await f.approve(board.id, true);
  const prepared = await f.api.act('prepare', { id: board.id }), task = prepared.tasks.find(t => t.task_id === 'research');
  const req = JSON.parse(await readFile(path.join(f.rootFor(board.id), `.moonsuite/products/moonflow/runs/${board.id}/dispatch/${task.request_id}.request.json`), 'utf8'));
  const file = board.source.local_evidence.files[0]; assert.ok(req.input_artifacts.includes(file.artifact_ref));
  await writeFile(path.join(f.rootFor(board.id), file.artifact_ref), 'changed');
  await assert.rejects(() => f.api.act('dispatch', { id: board.id, taskId: 'research' }), /bytes changed/);
  assert.deepEqual(f.submits, []);
  await writeFile(path.join(f.rootFor(board.id), file.artifact_ref), Buffer.from(localEvidence().content_base64, 'base64'));
  await f.api.act('dispatch', { id: board.id, taskId: 'research' });
  assert.equal(f.submittedInvocations.length, 1); assert.ok(f.submittedInvocations[0].request.input_artifacts.includes(file.artifact_ref));
}));

test('R657 synthetic native workflow: explicitly assigned specialist sources reach prepared dispatch and independent integration review', () => fixture(async f => {
  const original = await createEvidence(f, [localEvidence(['write'])]);
  const delegated = await f.api.act('specialists', { id: original.id, taskId: 'write', specialists: specialistSpecs() });
  const file = delegated.source.local_evidence.files[0];
  const input = { id: delegated.id, executionDigest: delegated.execution_digest, taskId: 'facts', artifactRefs: [file.artifact_ref], reason: 'Fact-check the captured source before integration' };
  const preview = await f.api.act('source-assignment-preview', input);
  const child = await f.api.act('source-assignment', { ...input, previewDigest: preview.execution_digest });
  assert.deepEqual(f.calls, []); assert.deepEqual(f.submits, []);
  await f.approve(delegated.id, true);
  await assert.rejects(() => f.api.act('prepare', { id: child.id }), /exact named/);
  await f.approve(child.id, false);
  await f.api.act('prepare', { id: child.id });
  await assert.rejects(() => f.api.act('dispatch', { id: child.id, taskId: 'research' }), /explicit approval/);
  await f.approve(child.id, true); // Synthetic adapter permission, no real provider.
  for (const taskId of ['research', 'design']) { await f.api.act('dispatch', { id: child.id, taskId }); await f.accept(child.id, taskId); }
  const ready = await f.api.act('prepare', { id: child.id });
  const facts = ready.tasks.find(task => task.task_id === 'facts');
  const request = JSON.parse(await readFile(path.join(f.rootFor(child.id), `.moonsuite/products/moonflow/runs/${child.id}/dispatch/${facts.request_id}.request.json`), 'utf8'));
  assert.ok(request.input_artifacts.includes(file.artifact_ref));
  const attemptCount = f.submittedInvocations.length;
  await writeFile(path.join(f.rootFor(child.id), file.artifact_ref), 'changed');
  await assert.rejects(() => f.api.act('dispatch', { id: child.id, taskId: 'facts' }), /bytes changed/);
  assert.equal(f.submittedInvocations.length, attemptCount);
  await writeFile(path.join(f.rootFor(child.id), file.artifact_ref), Buffer.from(localEvidence().content_base64, 'base64'));
  for (const taskId of ['facts', 'alternatives']) await f.api.act('dispatch', { id: child.id, taskId });
  const factsInvocation = f.submittedInvocations.find(item => item.request.work_item_id === 'facts');
  assert.ok(factsInvocation.request.input_artifacts.includes(file.artifact_ref));
  assert.match(factsInvocation.input.profile.instructions.join('\n'), /untrusted source material/);
  assert.ok(!f.submittedInvocations.find(item => item.request.work_item_id === 'alternatives').request.input_artifacts.includes(file.artifact_ref));
  let state = await f.api.act('prepare', { id: child.id }); assert.equal(state.tasks.find(task => task.task_id === 'write').dispatchable, false);
  await f.accept(child.id, 'facts');
  state = await f.api.act('prepare', { id: child.id }); assert.equal(state.tasks.find(task => task.task_id === 'write').dispatchable, false);
  await f.accept(child.id, 'alternatives');
  state = await f.api.act('prepare', { id: child.id }); assert.equal(state.tasks.find(task => task.task_id === 'write').dispatchable, true);
  await f.api.act('dispatch', { id: child.id, taskId: 'write' }); await f.accept(child.id, 'write');
  const result = await f.api.act('assemble', { id: child.id });
  assert.equal(result.assembly.entries.length, 5); assert.equal(result.assembly.customer_accepted, false);
  assert.equal((await f.api.state(delegated.id)).status, 'awaiting_import');
  assert.deepEqual(await readFile(path.join(f.rootFor(original.id), file.artifact_ref)), Buffer.from(localEvidence().content_base64, 'base64'));
}));

test('R606 reviewed targeted rework carries only local source mappings for affected tasks', () => fixture(async f => {
  const files = [localEvidence(['research', 'write']), { ...localEvidence(['design'], 'Design source\n'), name: 'design.txt' }];
  const board = await createEvidence(f, files); await f.approve(board.id, true); await f.api.act('prepare', { id: board.id });
  for (const id of ['research', 'design']) { await f.api.act('dispatch', { id: board.id, taskId: id }); await f.accept(board.id, id); }
  await f.api.act('prepare', { id: board.id }); await f.api.act('dispatch', { id: board.id, taskId: 'write' }); await f.accept(board.id, 'write');
  const child = await f.api.act('rework', { id: board.id, taskId: 'write', reason: 'Improve final wording' });
  assert.deepEqual(child.source.local_evidence.files.map(file => file.task_ids), [['write']]);
  assert.equal(child.source.local_evidence.files.length, 1);
  assert.deepEqual(await readFile(path.join(f.rootFor(child.id), child.source.local_evidence.files[0].artifact_ref)), Buffer.from(files[0].content_base64, 'base64'));
  assert.equal((await f.api.state(board.id)).source.local_evidence.files.length, 2);
}));

test('R606 refuses a symlinked input directory before creating source files outside its run', () => fixture(async f => {
  const payload = evidencePayload(f.directory), preview = await f.api.act('preview', payload);
  const root = f.rootFor(preview.id), outside = path.join(f.directory, 'elsewhere');
  await mkdir(root, { recursive: true }); await mkdir(outside); await symlink(outside, path.join(root, 'inputs'));
  await assert.rejects(() => f.api.act('create', { ...payload, previewDigest: preview.execution_digest }), /symlink/);
  assert.deepEqual(await readdir(outside), []); assert.deepEqual(f.calls, []);
}));


test('R630 synthetic native workflow: rework brief verifies retained carry-ins without exporting result content or changing execution', () => fixture(async f => {
  const board = await f.create(); await finish(f, board.id);
  const child = await f.api.act('rework', { id: board.id, taskId: 'research', reason: 'Correct source claims' });
  const calls = f.calls.length, submits = f.submits.length;
  const body = { id: child.id, ownerId: child.tasks[0].owner_id, executionDigest: child.execution_digest, includeSourceText: false };
  const brief = await f.api.act('delegation-brief', body);
  assert.match(brief.text, /Correction scope/); assert.match(brief.text, /Verified retained carry/); assert.match(brief.text, /Correct source claims/);
  assert.doesNotMatch(brief.text, /Reviewed content/); assert.equal(f.calls.length, calls); assert.equal(f.submits.length, submits);
  const ref = child.source.rework.carried_artifacts[0].artifact_ref;
  await writeFile(path.join(f.rootFor(child.id), ref), 'tampered carry-in');
  await assert.rejects(() => f.api.act('delegation-brief', { ...body, packetDigest: brief.content_digest }), /Retained output changed/);
}));
