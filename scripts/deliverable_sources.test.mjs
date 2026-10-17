import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile, mkdir, symlink, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { compileDeliverable, proposeEvidenceAssignment, proposeCapacity, proposeSpecialists, proposeOwnerHandoff, proposeDependencyRevision, proposeRework, verifyApproval, json } from './deliverable_workflow.mjs';
import { delegationBrief } from './delegation_brief.mjs';
import { createDeliverableHost } from './deliverable_host.mjs';
import { mountDeliverablePanel, renderDeliverablePanel } from '../frontend/opc_public/deliverable_panel.js';
import { harness } from './deliverable_panel_harness.mjs';

const now = '2026-10-13T00:00:00Z';
const plan = {
  contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'source-assignment-fixture' },
  workflow: { status: 'pending_review', accepted: false },
  authority_effects: Object.fromEntries(['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].map(key => [key, false])),
  owners: [{ owner_id: 'a', display_name: 'Ari' }, { owner_id: 'b', display_name: 'Bo' }],
  tasks: ['draft', 'review'].map((task_id, index) => ({ task_id, name: 'Same display name', owner_id: index ? 'b' : 'a', dependencies: index ? ['draft'] : [], acceptance_gate_ids: [task_id] })),
  acceptance_gates: ['draft', 'review'].map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Verify ' + id], required_evidence: ['Result ' + id] })),
};
const bytes = [Buffer.from('\ufeffSynthetic source A\r\nExact bytes.\r\n'), Buffer.from('Synthetic source B\n')];
const options = { planText: json(plan), outcome: 'Source-backed delegated brief', workspaceRoot: '/tmp/fixture', modelSelector: 'moongate/model', artifactRoot: '/tmp/fixture/data/deliverables', recordedAt: now,
  evidenceFiles: bytes.map((content, index) => ({ name: index ? 'other.md' : 'facts.md', content_base64: content.toString('base64'), task_ids: ['draft'] })) };
const specs = ['facts', 'alternatives'].map(task_id => ({ task_id, name: task_id, owner_id: 'b', acceptance_criteria: ['Check the assigned source'], required_evidence: ['Source-backed findings'] }));
const split = handoff => proposeSpecialists({ handoff, taskId: 'draft', specialists: specs, recordedAt: now });
const refs = handoff => handoff.source.local_evidence.files.map(file => file.artifact_ref);
const input = handoff => ({ handoff, executionDigest: handoff.execution_digest, taskId: 'facts', artifactRefs: [refs(handoff)[0]], reason: 'Verify the source claims', recordedAt: now });
const propose = (handoff, changes = {}) => proposeEvidenceAssignment({ ...input(handoff), ...changes });
const body = board => ({ id: board.id, executionDigest: board.execution_digest, taskId: 'facts', artifactRefs: [refs(board)[0]], reason: 'Verify the source claims' });

test('portable demonstration files support distinct specialist assignments and owner output', async () => {
  const names = ['interview-notes.md', 'alternatives.csv'];
  const contents = await Promise.all(names.map(name => readFile(new URL(`../docs/examples/source-assignment/${name}`, import.meta.url))));
  const original = compileDeliverable({ ...options, evidenceFiles: names.map((name, index) => ({ name, content_base64: contents[index].toString('base64'), task_ids: ['draft'] })) });
  const delegated = split(original), first = propose(delegated);
  const child = propose(first, { taskId: 'alternatives', artifactRefs: [refs(first)[1]], reason: 'Compare the supplied alternatives' });
  assert.deepEqual(child.source.local_evidence.files.map(file => file.task_ids), [['facts', 'draft'], ['alternatives', 'draft']]);
  const brief = delegationBrief({ handoff: child, ownerId: 'b', executionDigest: child.execution_digest, includeSourceText: true, evidenceBytes: new Map(refs(child).map((ref, index) => [ref, contents[index]])) });
  assert.match(brief.text, /invented demonstration material/); assert.match(brief.text, /synthetic_setup_assumption/);
  assert.equal(brief.source_refs.length, 2);
});

test('specialist receives explicit exact-byte inputs; graph gates, owners and all other assignments survive', () => {
  const original = compileDeliverable(options), parent = split(original), before = json(parent), child = propose(parent);
  const [ref, other] = refs(child);
  assert.equal(json(parent), before); assert.notEqual(child.id, parent.id);
  assert.deepEqual(child.source.tasks, parent.source.tasks);
  assert.deepEqual(child.source.specialists, parent.source.specialists);
  assert.deepEqual(child.graph.items.map(item => item.depends_on), parent.graph.items.map(item => item.depends_on));
  assert.deepEqual(child.source.local_evidence.files.map(({ task_ids, ...file }) => file), parent.source.local_evidence.files.map(({ task_ids, ...file }) => file));
  assert.deepEqual(child.source.local_evidence.files[0].task_ids, ['facts', 'draft']);
  assert.deepEqual(child.source.local_evidence.files[1].task_ids, ['draft']);
  assert.ok(child.graph.items.find(item => item.work_item_id === 'facts').input_artifacts.includes(ref));
  assert.ok(!child.graph.items.find(item => item.work_item_id === 'facts').input_artifacts.includes(other));
  assert.ok(!child.graph.items.find(item => item.work_item_id === 'alternatives').input_artifacts.includes(ref));
  assert.match(child.requests['inputs/facts.json'].profile.instructions.join('\n'), /untrusted source material/);
  assert.match(child.requests['inputs/facts.json'].profile.instructions.join('\n'), new RegExp(ref.replaceAll('.', '\\.')));
  assert.match(child.requests['inputs/alternatives.json'].profile.instructions.join('\n'), /Source assignments were explicitly revised/i);
  assert.equal(child.source.plan_digest, original.source.plan_digest);
  assert.throws(() => verifyApproval(child, { contract_id: 'moonproj.deliverable-review.v1', decision: 'approved', execution_digest: parent.execution_digest, reviewer_id: 'operator', reviewed_at: now }), /exact named/);
  const change = child.source.evidence_assignments[0];
  assert.equal(change.parent_id, parent.id); assert.equal(change.parent_execution_digest, parent.execution_digest);
  assert.deepEqual(change.previous_artifact_refs, []); assert.deepEqual(change.next_artifact_refs, [ref]);
  assert.deepEqual(change.added_artifact_refs, [ref]); assert.deepEqual(change.removed_artifact_refs, []);
  const brief = delegationBrief({ handoff: child, ownerId: 'b', executionDigest: child.execution_digest, includeSourceText: true, evidenceBytes: new Map(refs(child).map((ref, i) => [ref, bytes[i]])) });
  assert.deepEqual(brief.source_refs, [ref]); assert.match(brief.text, /Source assignment history/); assert.match(brief.text, /Synthetic source A/); assert.doesNotMatch(brief.text, /Synthetic source B/);
});

test('canonical selection, assignment removal, 32-entry history and capacity/owner/prerequisite composition', () => {
  const original = compileDeliverable(options), parent = split(original);
  const child = propose(parent, { artifactRefs: refs(parent).toReversed() });
  assert.equal(child.id, propose(parent, { artifactRefs: refs(parent), recordedAt: '2026-10-14T00:00:00Z' }).id);
  const removed = propose(child, { artifactRefs: [] });
  assert.deepEqual(removed.source.evidence_assignments[1].removed_artifact_refs, refs(child));
  assert.ok(!removed.graph.items.find(item => item.work_item_id === 'facts').input_artifacts.includes(refs(child)[0]));
  const capacity = proposeCapacity({ handoff: parent, ownerLimits: { a: 1, b: 1 }, recordedAt: now });
  const assigned = propose(capacity); assert.deepEqual(assigned.source.capacity, capacity.source.capacity); assert.deepEqual(assigned.source.tasks, capacity.source.tasks);
  const capacityAfter = proposeCapacity({ handoff: propose(parent), ownerLimits: { a: 1, b: 1 }, recordedAt: now });
  assert.deepEqual(capacityAfter.source.evidence_assignments, propose(parent).source.evidence_assignments);
  const owner = proposeOwnerHandoff({ handoff: original, taskId: 'draft', ownerId: 'b', reason: 'Available owner', planText: options.planText, recordedAt: now });
  assert.equal(propose(owner, { taskId: 'review' }).source.tasks[0].owner_id, 'b');
  const dependencies = proposeDependencyRevision({ handoff: original, taskId: 'review', dependencies: [], reason: 'Independent review preparation', executionDigest: original.execution_digest, recordedAt: now });
  assert.deepEqual(propose(dependencies, { taskId: 'review' }).source.dependency_revisions, dependencies.source.dependency_revisions);
  let revision = parent;
  for (let i = 0; i < 32; i++) revision = propose(revision, { artifactRefs: i % 2 ? [] : [refs(parent)[0]] });
  assert.throws(() => propose(revision), /32 revisions/);
});

test('no-op, orphaned sources, unknown paths/task, malformed/stale scope, no sources and rework reject unchanged', () => {
  const parent = split(compileDeliverable(options)), before = json(parent);
  for (const changes of [{ artifactRefs: [] }, { artifactRefs: null }, { artifactRefs: 'facts.md' }, { artifactRefs: [null] }, { artifactRefs: ['../secret'] }, { artifactRefs: ['/tmp/secret'] },
    { artifactRefs: [refs(parent)[0], refs(parent)[0]] }, { taskId: 'missing' }, { reason: '' }, { reason: ' ' }, { reason: 'x'.repeat(4097) }, { executionDigest: undefined }, { executionDigest: 'stale' }]) {
    assert.throws(() => propose(parent, changes)); assert.equal(json(parent), before);
  }
  assert.throws(() => propose(parent, { taskId: 'draft', artifactRefs: [] }), /last assignment/);
  const noSources = compileDeliverable({ ...options, evidenceFiles: [] });
  assert.throws(() => proposeEvidenceAssignment({ ...input(parent), handoff: noSources, executionDigest: noSources.execution_digest }), /no saved local evidence/);
  const simple = compileDeliverable(options);
  const rework = proposeRework({ handoff: simple, projection: null, taskId: 'draft', reason: 'Redo all', recordedAt: now });
  assert.throws(() => propose(rework, { taskId: 'review' }), /rework scope/);
});

async function fixture(run) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-sources-'));
  let time = now;
  const config = { data: path.join(root, 'data'), config: async () => ({}), readOperatorJson: async () => { throw Error('No operator review'); }, runMoonflow: async () => { throw Error('Forbidden native call'); }, now: () => time };
  const api = createDeliverableHost(config);
  try {
    const value = { ...options, workspaceRoot: root }, preview = await api.act('preview', value);
    const original = await api.act('create', { ...value, previewDigest: preview.execution_digest });
    const board = await api.act('specialists', { id: original.id, taskId: 'draft', specialists: specs });
    await run({ root, api, board, original, config, tick: () => { time = '2026-10-14T00:00:00Z'; } });
  } finally { await rm(root, { recursive: true, force: true }); }
}

test('no-write preview, exact save, restarted retry and interrupted materialization preserve original bytes', () => fixture(async ({ root, api, board, config, tick }) => {
  const base = path.join(root, 'data/deliverables'), before = (await readdir(base, { recursive: true })).sort();
  const preview = await api.act('source-assignment-preview', body(board));
  assert.deepEqual((await readdir(base, { recursive: true })).sort(), before);
  await assert.rejects(() => api.act('source-assignment', body(board)), /Preview/);
  await assert.rejects(() => api.act('source-assignment', { ...body(board), reason: 'Changed', previewDigest: preview.execution_digest }), /Preview/);
  const saved = await api.act('source-assignment', { ...body(board), previewDigest: preview.execution_digest }); tick();
  assert.equal(saved.status, 'awaiting_import'); const restarted = createDeliverableHost(config);
  assert.equal((await restarted.act('source-assignment', { ...body(board), previewDigest: preview.execution_digest })).id, saved.id);
  assert.equal((await restarted.list()).length, 3); assert.deepEqual((await restarted.state(board.id)).source, board.source);
  for (const ref of ['source-plan.json', ...refs(board)]) assert.deepEqual(await readFile(path.join(base, board.id, ref)), await readFile(path.join(base, saved.id, ref)));
  const childFile = path.join(base, saved.id, 'inputs/facts.json'); await rm(childFile);
  await restarted.act('source-assignment', { ...body(board), previewDigest: preview.execution_digest });
  assert.match(await readFile(childFile, 'utf8'), /Local source assignments/);
  await writeFile(childFile, 'different bytes');
  await assert.rejects(() => restarted.act('source-assignment', { ...body(board), previewDigest: preview.execution_digest }), /differs/);
  await assert.rejects(() => restarted.act('prepare', { id: saved.id }), /deliverable_review_file/);
}));

test('imported and pending-preparation parents reject both preview and save without native calls', () => fixture(async ({ root, api, board }) => {
  const request = body(board), preview = await api.act('source-assignment-preview', request), run = path.join(root, 'data/deliverables', board.id);
  const projection = path.join(run, '.moonsuite/products/moonflow/runs', board.id, 'projection.json');
  await mkdir(path.dirname(projection), { recursive: true }); await writeFile(projection, '{}');
  for (const action of ['source-assignment-preview', 'source-assignment']) await assert.rejects(() => api.act(action, { ...request, previewDigest: preview.execution_digest }), /unimported board/);
  await rm(projection); await mkdir(path.join(run, 'runtime')); await writeFile(path.join(run, 'runtime/prepare-intent.json'), '{}');
  for (const action of ['source-assignment-preview', 'source-assignment']) await assert.rejects(() => api.act(action, { ...request, previewDigest: preview.execution_digest }), /pending native preparation/);
}));

for (const marker of ['projection', 'prepare-intent']) {
  test(`present corrupt ${marker} never masquerades as absent native state after preview`, () => fixture(async ({ root, api, board }) => {
    const request = body(board), preview = await api.act('source-assignment-preview', request);
    const base = path.join(root, 'data/deliverables'), run = path.join(base, board.id);
    const ref = marker === 'projection' ? `.moonsuite/products/moonflow/runs/${board.id}/projection.json` : 'runtime/prepare-intent.json';
    const file = path.join(run, ref), original = await readFile(path.join(run, 'handoff.json'));
    await mkdir(path.dirname(file), { recursive: true });
    // Null is the independent-review reproduction. Other falsy JSON values,
    // malformed JSON and nonregular entries must also require reconciliation.
    for (const content of ['null\n', 'false\n', '0\n', '""\n', '', '{broken']) {
      await writeFile(file, content);
      for (const action of ['source-assignment-preview', 'source-assignment']) {
        await assert.rejects(() => api.act(action, { ...request, previewDigest: preview.execution_digest }), /pending native preparation/);
      }
      assert.equal((await readdir(base)).length, 2);
      assert.deepEqual(await readFile(path.join(run, 'handoff.json')), original);
      assert.equal(await readFile(file, 'utf8'), content);
    }
    await rm(file); await mkdir(file);
    for (const action of ['source-assignment-preview', 'source-assignment']) await assert.rejects(() => api.act(action, { ...request, previewDigest: preview.execution_digest }), /pending native preparation/);
    await rm(file, { recursive: true }); await symlink(path.join(root, 'missing-native-state'), file);
    for (const action of ['source-assignment-preview', 'source-assignment']) await assert.rejects(() => api.act(action, { ...request, previewDigest: preview.execution_digest }), /pending native preparation/);
    assert.equal((await readdir(base)).length, 2);
  }));
}

for (const target of ['source-plan.json', 'selected-evidence', 'unselected-evidence']) for (const fault of ['changed', 'missing', 'symlink']) {
  test(`${fault} ${target} blocks preview/save without a child`, () => fixture(async ({ root, api, board }) => {
    const preview = await api.act('source-assignment-preview', body(board)), base = path.join(root, 'data/deliverables');
    const ref = target === 'source-plan.json' ? target : refs(board)[target === 'selected-evidence' ? 0 : 1], file = path.join(base, board.id, ref);
    if (fault === 'changed') await writeFile(file, 'Changed');
    else { const content = await readFile(file); await rm(file); if (fault === 'symlink') { const other = path.join(root, 'replacement'); await writeFile(other, content); await symlink(other, file); } }
    for (const action of ['source-assignment-preview', 'source-assignment']) await assert.rejects(() => api.act(action, { ...body(board), previewDigest: preview.execution_digest }));
    assert.equal((await readdir(base)).length, 2);
  }));
}

const turn = () => new Promise(resolve => setTimeout(resolve, 0));
const select = (h, selector, value) => { const field = h.get(selector); field.value = value; field.events.change({ target: field }); };
const fill = (h, board) => { select(h, '[data-source-task]', 'facts'); h.check(`[data-source-ref="${refs(board)[0]}"]`); h.input('sourceReason', 'Verify selected facts'); };
const localFetch = api => async (url, opts) => {
  try { return { ok: true, json: async () => opts ? await api.act(url.split('/').at(-1), JSON.parse(opts.body)) : { deliverables: await api.list() } }; }
  catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
};

test('mounted source editor previews actual task mapping, invalidates changed reason/selection, and saves', () => fixture(async ({ api, board }) => {
  const h = harness(), dispose = mountDeliverablePanel(h.host, { fetcher: localFetch(api) });
  try {
    await new Promise(resolve => setTimeout(resolve, 20)); select(h, '[data-select]', board.id); fill(h, board);
    await h.click('source-assignment-preview'); assert.equal(h.get('[data-action="source-assignment"]').disabled, false); assert.match(h.host.innerHTML, /Added sources: facts.md/);
    const staleSave = h.get('[data-action="source-assignment"]'); h.input('sourceReason', '<script>new reason</script>'); await staleSave.events.click(); assert.equal((await api.list()).length, 2);
    await h.click('source-assignment-preview'); assert.match(h.host.innerHTML, /&lt;script&gt;new reason&lt;\/script&gt;/);
    h.check(`[data-source-ref="${refs(board)[1]}"]`); assert.equal(h.get('[data-action="source-assignment"]').disabled, true);
    await h.click('source-assignment-preview'); select(h, '[data-source-task]', 'alternatives'); assert.equal(h.get('[data-action="source-assignment"]').disabled, true);
    fill(h, board); await h.click('source-assignment-preview'); await h.click('source-assignment');
    assert.equal((await api.list()).length, 3); assert.match(h.host.innerHTML, /Source assignment history/); assert.match(h.host.innerHTML, /parent review cannot authorize/);
  } finally { dispose(); }
}));

test('board switch and detached controls cannot apply previous task sources', () => fixture(async ({ api, board, original }) => {
  const h = harness(), dispose = mountDeliverablePanel(h.host, { fetcher: localFetch(api) });
  try {
    await new Promise(resolve => setTimeout(resolve, 20)); select(h, '[data-select]', board.id); fill(h, board); await h.click('source-assignment-preview');
    const staleSave = h.get('[data-action="source-assignment"]'), staleFile = h.get(`[data-source-ref="${refs(board)[0]}"]`);
    select(h, '[data-select]', original.id); await staleSave.events.click(); staleFile.checked = false; staleFile.events.change({ target: staleFile });
    assert.equal(h.get('[data-action="source-assignment"]').disabled, true); assert.equal((await api.list()).length, 2);
  } finally { dispose(); }
}));

for (const cancel of ['source-assignment-cancel', 'cancel-draft', 'dispose']) {
  test(`${cancel} prevents a late source preview from restoring discarded state`, () => fixture(async ({ api, board }) => {
    const h = harness(); let release; const hold = new Promise(resolve => { release = resolve; }), base = localFetch(api);
    const fetcher = async (url, opts) => { const response = await base(url, opts); if (url.endsWith('/source-assignment-preview')) await hold; return response; };
    const dispose = mountDeliverablePanel(h.host, { fetcher });
    try {
      await new Promise(resolve => setTimeout(resolve, 20)); select(h, '[data-select]', board.id); fill(h, board);
      const pending = h.click('source-assignment-preview'); await turn();
      if (cancel === 'dispose') dispose(); else { await h.click(cancel); fill(h, board); h.input('sourceReason', 'Newer draft'); }
      const after = h.host.innerHTML; release(); await pending;
      if (cancel === 'dispose') assert.equal(h.host.innerHTML, after);
      else { assert.equal(h.get('[data-action="source-assignment"]').disabled, true); assert.equal(h.get('[data-field="sourceReason"]').value, 'Newer draft'); }
      assert.equal((await api.list()).length, 2);
    } finally { release(); dispose(); }
  }));
}

test('repeated saves serialize; save cannot be cancelled as if no child exists', () => fixture(async ({ api, board }) => {
  const h = harness(); let release; const hold = new Promise(resolve => { release = resolve; }); let saves = 0; const base = localFetch(api);
  const fetcher = async (url, opts) => { if (url.endsWith('/source-assignment')) { saves++; await hold; } return base(url, opts); };
  const dispose = mountDeliverablePanel(h.host, { fetcher });
  try {
    await new Promise(resolve => setTimeout(resolve, 20)); select(h, '[data-select]', board.id); fill(h, board); await h.click('source-assignment-preview');
    const old = h.get('[data-action="source-assignment"]'); const pending = old.events.click(); await old.events.click();
    assert.equal(h.get('[data-action="source-assignment-cancel"]').disabled, true); await h.click('source-assignment-cancel');
    assert.equal(saves, 1); release(); await pending; assert.equal((await api.list()).length, 3);
  } finally { release(); dispose(); }
}));

test('editor is absent on boards without sources, imported boards and rework scopes', () => {
  const original = compileDeliverable(options), base = { entries: [], selected: original.id, draft: {}, busy: false };
  for (const item of [{ id: original.id, source: original.source, tasks: original.source.tasks, status: 'in_progress' },
    { id: original.id, source: { ...original.source, local_evidence: undefined }, tasks: original.source.tasks, status: 'awaiting_import' },
    { id: original.id, source: { ...original.source, rework: { invalidated_task_ids: ['draft'], retained: [] } }, tasks: original.source.tasks, status: 'awaiting_import' }]) {
    assert.doesNotMatch(renderDeliverablePanel({ ...base, entries: [item] }), /data-source-task/);
  }
});
