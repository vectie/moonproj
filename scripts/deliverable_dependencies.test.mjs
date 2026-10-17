import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile, mkdir, symlink, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { compileDeliverable, proposeDependencyRevision, proposeCapacity, proposeSpecialists, proposeOwnerHandoff, verifyApproval, json } from './deliverable_workflow.mjs';
import { delegationBrief } from './delegation_brief.mjs';
import { createDeliverableHost } from './deliverable_host.mjs';
import { mountDeliverablePanel } from '../frontend/opc_public/deliverable_panel.js';
import { harness } from './deliverable_panel_harness.mjs';

const now = '2026-10-13T00:00:00Z';
const ids = ['research', 'draft', 'review', 'facts'];
const plan = {
  contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'prerequisite-revision' },
  workflow: { status: 'pending_review', accepted: false },
  authority_effects: Object.fromEntries(['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].map(key => [key, false])),
  owners: [{ owner_id: 'a', display_name: 'Ari' }, { owner_id: 'b', display_name: 'Bo' }],
  tasks: ids.map((task_id, index) => ({ task_id, name: index < 2 ? 'Same display name' : task_id, owner_id: index % 2 ? 'b' : 'a',
    dependencies: index === 1 ? ['research'] : index === 2 ? ['draft'] : [], acceptance_gate_ids: [task_id] })),
  acceptance_gates: ids.map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Verify ' + id], required_evidence: ['Result ' + id] })),
};
const sourceBytes = Buffer.from('\ufeffOriginal source\r\nExact bytes.\r\n');
const options = { planText: json(plan), outcome: 'Source-backed delegated brief', workspaceRoot: '/tmp/fixture', modelSelector: 'moongate/model',
  artifactRoot: '/tmp/fixture/data/deliverables', recordedAt: now,
  evidenceFiles: [{ name: 'facts.md', content_base64: sourceBytes.toString('base64'), task_ids: ['facts', 'draft'] }] };
const input = handoff => ({ handoff, executionDigest: handoff.execution_digest, taskId: 'draft', dependencies: ['facts'], reason: 'Use the independently checked facts', recordedAt: now });
const propose = (handoff, changes = {}) => proposeDependencyRevision({ ...input(handoff), ...changes });
const body = board => ({ id: board.id, executionDigest: board.execution_digest, taskId: 'draft', dependencies: ['facts'], reason: 'Use the independently checked facts' });

test('prerequisite revision changes real Flow edges and Claw scope, preserves original/gates/sources and invalidates review', () => {
  const original = compileDeliverable(options), before = json(original), child = propose(original);
  assert.equal(json(original), before);
  assert.notEqual(child.id, original.id); assert.notEqual(child.execution_digest, original.execution_digest);
  assert.deepEqual(child.graph.items.map(item => item.depends_on), [[], ['facts'], ['draft'], []]);
  assert.deepEqual(child.source.tasks.map(({ dependencies, ...task }) => task), original.source.tasks.map(({ dependencies, ...task }) => task));
  assert.deepEqual(child.source.local_evidence, original.source.local_evidence);
  assert.equal(child.source.plan_digest, original.source.plan_digest);
  const change = child.source.dependency_revisions[0];
  assert.deepEqual(change.previous_dependencies, ['research']); assert.deepEqual(change.next_dependencies, ['facts']);
  assert.deepEqual(change.added_dependencies, ['facts']); assert.deepEqual(change.removed_dependencies, ['research']);
  assert.deepEqual(change.affected_task_ids, ['draft', 'review']);
  assert.equal(change.parent_execution_digest, original.execution_digest); assert.equal(change.parent_id, original.id);
  assert.match(child.requests['inputs/draft.json'].profile.instructions.join('\n'), /Current task prerequisites/);
  assert.throws(() => verifyApproval(child, { contract_id: 'moonproj.deliverable-review.v1', decision: 'approved', execution_digest: original.execution_digest, reviewer_id: 'operator', reviewed_at: now }), /exact named/);
  assert.equal(propose(original, { recordedAt: '2026-10-14T00:00:00Z' }).id, child.id);
  const brief = delegationBrief({ handoff: child, ownerId: 'b', executionDigest: child.execution_digest, includeSourceText: false,
    evidenceBytes: new Map([[child.source.local_evidence.files[0].artifact_ref, sourceBytes]]) });
  assert.match(brief.text, /Prerequisite revision context/); assert.match(brief.text, /Use the independently checked facts/);
});

test('add/remove/canonical order, retained history and owner/capacity/specialist composition', () => {
  const parent = compileDeliverable(options);
  const child = propose(parent, { dependencies: ['facts', 'research'] });
  assert.deepEqual(child.source.tasks[1].dependencies, ['research', 'facts']);
  assert.equal(propose(parent, { dependencies: ['research', 'facts'] }).id, child.id);
  const independent = propose(child, { dependencies: [], reason: 'The draft uses only its assigned source file' });
  assert.deepEqual(independent.source.tasks[1].dependencies, []); assert.equal(independent.source.dependency_revisions.length, 2);
  assert.equal(independent.source.dependency_revisions[1].parent_id, child.id);
  const owner = proposeOwnerHandoff({ handoff: child, taskId: 'draft', ownerId: 'a', reason: 'Owner available', planText: options.planText, recordedAt: now });
  assert.deepEqual(owner.source.dependency_revisions, child.source.dependency_revisions);
  assert.equal(propose(owner, { dependencies: [] }).source.tasks[1].owner_id, 'a');
  const capacity = proposeCapacity({ handoff: child, ownerLimits: { a: 1, b: 1 }, recordedAt: now });
  assert.deepEqual(capacity.source.dependency_revisions, child.source.dependency_revisions);
  assert.ok(capacity.source.tasks[1].dependencies.includes('facts'));
  const specialists = proposeSpecialists({ handoff: child, taskId: 'draft', specialists: ['one', 'two'].map(task_id => ({ task_id, name: task_id, owner_id: 'a', acceptance_criteria: ['Check it'], required_evidence: ['Notes'] })), recordedAt: now });
  assert.deepEqual(specialists.source.dependency_revisions, child.source.dependency_revisions);
  assert.ok(specialists.source.tasks.find(task => task.task_id === 'one').dependencies.includes('facts'));
  for (const scoped of [capacity, specialists]) assert.throws(() => propose(scoped), /before capacity/);
});

test('cycles/self/missing/duplicate/no-op/malformed/stale scope/reason reject without mutating parent', () => {
  const parent = compileDeliverable(options), before = json(parent);
  for (const change of [
    { dependencies: ['review'] }, { dependencies: ['draft'] }, { dependencies: ['missing'] }, { dependencies: ['facts', 'facts'] },
    { dependencies: ['research'] }, { dependencies: null }, { dependencies: 'facts' }, { dependencies: [null] }, { dependencies: ['__proto__'] },
    { taskId: 'missing' }, { reason: '' }, { reason: ' ' }, { reason: 'x'.repeat(4097) }, { executionDigest: undefined }, { executionDigest: 'sha256:stale' },
  ]) { assert.throws(() => propose(parent, change)); assert.equal(json(parent), before); }
  assert.throws(() => propose(parent, { taskId: 'research', dependencies: ['review'] }), /cycle/);
  let revision = parent;
  for (let i = 0; i < 32; i++) revision = propose(revision, { dependencies: i % 2 ? ['research'] : ['facts'] });
  assert.throws(() => propose(revision), /32 revisions/);
});

async function fixture(run) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-prerequisites-'));
  let time = now;
  const config = { data: path.join(root, 'data'), config: async () => ({}), readOperatorJson: async () => { throw Error('No operator review'); },
    runMoonflow: async () => { throw Error('Forbidden native call'); }, now: () => time };
  const api = createDeliverableHost(config);
  try {
    const value = { ...options, workspaceRoot: root };
    const preview = await api.act('preview', value);
    const board = await api.act('create', { ...value, previewDigest: preview.execution_digest });
    await run({ root, api, board, config, tick: () => { time = '2026-10-14T00:00:00Z'; } });
  } finally { await rm(root, { recursive: true, force: true }); }
}

test('durable no-write preview/save/restart/exact retry repairs interruption and keeps original bytes', () => fixture(async ({ root, api, board, config, tick }) => {
  const preview = await api.act('prerequisites-preview', body(board));
  assert.equal((await api.list()).length, 1); assert.equal((await readdir(path.join(root, 'data/deliverables'))).length, 1);
  await assert.rejects(() => api.act('prerequisites', body(board)), /Preview/);
  await assert.rejects(() => api.act('prerequisites', { ...body(board), reason: 'Changed', previewDigest: preview.execution_digest }), /Preview/);
  assert.equal((await api.list()).length, 1);
  const saved = await api.act('prerequisites', { ...body(board), previewDigest: preview.execution_digest });
  assert.equal(saved.status, 'awaiting_import'); tick();
  const restarted = createDeliverableHost(config);
  assert.equal((await restarted.act('prerequisites', { ...body(board), previewDigest: preview.execution_digest })).id, saved.id);
  assert.equal((await restarted.list()).length, 2);
  const base = path.join(root, 'data/deliverables');
  for (const ref of ['source-plan.json', board.source.local_evidence.files[0].artifact_ref]) assert.deepEqual(await readFile(path.join(base, board.id, ref)), await readFile(path.join(base, saved.id, ref)));
  const original = (await restarted.list()).find(value => value.id === board.id); assert.deepEqual(original.graph, board.graph);
  await assert.rejects(() => restarted.act('prepare', { id: saved.id }), /deliverable_review_file/);
  // A saved handoff whose materialization was interrupted can be repaired from
  // the same verified parent. Different bytes are never overwritten.
  const childFile = path.join(base, saved.id, 'inputs/draft.json'); await rm(childFile);
  await restarted.act('prerequisites', { ...body(board), previewDigest: preview.execution_digest });
  assert.match(await readFile(childFile, 'utf8'), /Current task prerequisites/);
  await writeFile(childFile, 'different bytes');
  await assert.rejects(() => restarted.act('prerequisites', { ...body(board), previewDigest: preview.execution_digest }), /differs/);
}));

test('invalid proposals have no saved child and no native calls', () => fixture(async ({ api, board }) => {
  for (const dependencies of [['review'], ['draft'], ['missing'], ['facts', 'facts'], ['research'], null]) {
    await assert.rejects(() => api.act('prerequisites-preview', { ...body(board), dependencies }));
    await assert.rejects(() => api.act('prerequisites', { ...body(board), dependencies, previewDigest: board.execution_digest }));
    assert.equal((await api.list()).length, 1);
  }
}));

test('imported or interrupted-preparation parent rejects preview and save', () => fixture(async ({ root, api, board }) => {
  const request = body(board), preview = await api.act('prerequisites-preview', request);
  const run = path.join(root, 'data/deliverables', board.id);
  const projection = path.join(run, '.moonsuite/products/moonflow/runs', board.id, 'projection.json');
  await mkdir(path.dirname(projection), { recursive: true }); await writeFile(projection, '{}');
  await assert.rejects(() => api.act('prerequisites-preview', request), /unimported board/);
  await assert.rejects(() => api.act('prerequisites', { ...request, previewDigest: preview.execution_digest }), /unimported board/);
  await rm(projection); await mkdir(path.join(run, 'runtime')); await writeFile(path.join(run, 'runtime/prepare-intent.json'), '{}');
  await assert.rejects(() => api.act('prerequisites-preview', request), /pending native preparation/);
  await assert.rejects(() => api.act('prerequisites', { ...request, previewDigest: preview.execution_digest }), /pending native preparation/);
}));

for (const ref of ['source-plan.json', 'evidence']) for (const fault of ['changed', 'missing', 'symlink']) {
  test(`${fault} ${ref} prevents preview/save and leaves parent only`, () => fixture(async ({ root, api, board }) => {
    const preview = await api.act('prerequisites-preview', body(board));
    const relative = ref === 'evidence' ? board.source.local_evidence.files[0].artifact_ref : ref;
    const file = path.join(root, 'data/deliverables', board.id, relative);
    if (fault === 'changed') await writeFile(file, 'Changed bytes');
    else { const bytes = await readFile(file); await rm(file); if (fault === 'symlink') { const other = path.join(root, 'replacement'); await writeFile(other, bytes); await symlink(other, file); } }
    await assert.rejects(() => api.act('prerequisites-preview', body(board)));
    await assert.rejects(() => api.act('prerequisites', { ...body(board), previewDigest: preview.execution_digest }));
    assert.equal((await readdir(path.join(root, 'data/deliverables'))).length, 1);
  }));
}

const turn = () => new Promise(resolve => setTimeout(resolve, 0));
const select = (h, selector, value) => { const field = h.get(selector); field.value = value; field.events.change({ target: field }); };
const fill = h => { select(h, '[data-dependency-task]', 'draft'); h.check('[data-dependency-prerequisite="research"]', false); h.check('[data-dependency-prerequisite="facts"]'); h.input('dependencyReason', 'Use checked facts'); };
const localFetch = api => async (url, opts) => {
  try { return { ok: true, json: async () => opts ? await api.act(url.split('/').at(-1), JSON.parse(opts.body)) : { deliverables: await api.list() } }; }
  catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
};

test('mounted editor selects stable IDs, invalidates on reason/checkbox/task and saves a complete inspectable child', () => fixture(async ({ api }) => {
  const h = harness(), dispose = mountDeliverablePanel(h.host, { fetcher: localFetch(api) });
  try {
    await new Promise(resolve => setTimeout(resolve, 20)); fill(h);
    await h.click('prerequisites-preview'); assert.equal(h.get('[data-action="prerequisites"]').disabled, false);
    assert.match(h.host.innerHTML, /Added: facts/); assert.match(h.host.innerHTML, /Removed: research/); assert.match(h.host.innerHTML, /draft, review/);
    const staleSave = h.get('[data-action="prerequisites"]'); h.input('dependencyReason', '<script>changed</script>');
    await staleSave.events.click(); assert.equal((await api.list()).length, 1);
    await h.click('prerequisites-preview'); assert.match(h.host.innerHTML, /&lt;script&gt;changed&lt;\/script&gt;/);
    h.check('[data-dependency-prerequisite="research"]'); assert.equal(h.get('[data-action="prerequisites"]').disabled, true);
    await h.click('prerequisites-preview'); select(h, '[data-dependency-task]', 'review'); assert.equal(h.get('[data-action="prerequisites"]').disabled, true);
    fill(h); await h.click('prerequisites-preview'); await h.click('prerequisites');
    assert.equal((await api.list()).length, 2); assert.match(h.host.innerHTML, /Prerequisite revision history/); assert.match(h.host.innerHTML, /parent review cannot authorize/);
  } finally { dispose(); }
}));

test('selecting another saved board clears preview and detached controls cannot mutate it', () => fixture(async ({ api, board }) => {
  const preview = await api.act('prerequisites-preview', body(board)); const child = await api.act('prerequisites', { ...body(board), previewDigest: preview.execution_digest });
  const h = harness(), dispose = mountDeliverablePanel(h.host, { fetcher: localFetch(api) });
  try {
    await new Promise(resolve => setTimeout(resolve, 20)); select(h, '[data-select]', board.id); fill(h); await h.click('prerequisites-preview');
    const oldSave = h.get('[data-action="prerequisites"]'), oldField = h.get('[data-dependency-prerequisite="facts"]');
    select(h, '[data-select]', child.id); await oldSave.events.click(); oldField.checked = false; oldField.events.change({ target: oldField });
    assert.equal(h.get('[data-action="prerequisites"]').disabled, true); assert.equal((await api.list()).length, 2);
  } finally { dispose(); }
}));

for (const cancel of ['prerequisites-cancel', 'cancel-draft', 'dispose']) {
  test(`${cancel} prevents a late preview restoring discarded scope`, () => fixture(async ({ api }) => {
    const h = harness(); let release; const hold = new Promise(resolve => { release = resolve; });
    const base = localFetch(api); const fetcher = async (url, opts) => { const response = await base(url, opts); if (url.endsWith('/prerequisites-preview')) await hold; return response; };
    const dispose = mountDeliverablePanel(h.host, { fetcher });
    try {
      await new Promise(resolve => setTimeout(resolve, 20)); fill(h); const pending = h.click('prerequisites-preview'); await turn();
      if (cancel === 'dispose') dispose(); else { await h.click(cancel); fill(h); h.input('dependencyReason', 'Newer draft'); }
      const after = h.host.innerHTML; release(); await pending;
      if (cancel === 'dispose') assert.equal(h.host.innerHTML, after);
      else { assert.equal(h.get('[data-action="prerequisites"]').disabled, true); assert.equal(h.get('[data-field="dependencyReason"]').value, 'Newer draft'); }
      assert.equal((await api.list()).length, 1);
    } finally { release(); dispose(); }
  }));
}

test('repeat preview/save serialized; save cannot be cancelled as if no board was created', () => fixture(async ({ api }) => {
  const h = harness(); let release; const hold = new Promise(resolve => { release = resolve; }); let saves = 0;
  const base = localFetch(api), fetcher = async (url, opts) => { if (url.endsWith('/prerequisites')) { saves++; await hold; } return base(url, opts); };
  const dispose = mountDeliverablePanel(h.host, { fetcher });
  try {
    await new Promise(resolve => setTimeout(resolve, 20)); fill(h); await h.click('prerequisites-preview');
    const old = h.get('[data-action="prerequisites"]'); const pending = old.events.click(); await old.events.click();
    assert.equal(h.get('[data-action="prerequisites-cancel"]').disabled, true); await h.click('prerequisites-cancel');
    assert.equal(saves, 1); release(); await pending; assert.equal((await api.list()).length, 2);
  } finally { release(); dispose(); }
}));
