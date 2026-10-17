import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import net from 'node:net';
import { mkdtemp, readFile, rm, writeFile, readdir, mkdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const repository = path.resolve(import.meta.dirname, '..');
async function freePort() {
  const server = net.createServer(); await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port; await new Promise(resolve => server.close(resolve)); return port;
}
async function start(data, port) {
  const process = spawn(globalThis.process.execPath, ['scripts/portfolio_host.mjs'], { cwd: repository,
    env: { ...globalThis.process.env, MOONPROJ_PORT: String(port), MOONPROJ_PORTFOLIO_DATA: data, MOONPROJ_DIST: path.join(repository, 'frontend/opc_public'), MOONPROJ_EXECUTION_CONFIG: '' }, stdio: ['ignore', 'pipe', 'pipe'] });
  await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => { process.kill(); reject(Error(`Host startup timed out: ${output}`)); }, 5000);
    process.stderr.on('data', data => { output += data; });
    process.stdout.on('data', data => { output += data; if (output.includes('MoonProj portfolio:')) { clearTimeout(timer); resolve(); } });
    process.once('exit', code => { clearTimeout(timer); reject(Error(`Host exited ${code}: ${output}`)); });
  });
  return async () => { const closed = new Promise(resolve => process.once('exit', resolve)); process.kill('SIGTERM'); await closed; };
}

test('source assignment HTTP journey: intake → specialists → explicit sources → saved scope → owner brief after restart', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-source-assignment-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'sources-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }, { owner_id: 'reviewer', display_name: 'Reviewer' }],
    tasks: ['draft', 'review'].map((id, index) => ({ task_id: id, name: id, owner_id: index ? 'reviewer' : 'writer', dependencies: index ? ['draft'] : [], acceptance_gate_ids: [id] })),
    acceptance_gates: ['draft', 'review'].map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Check ' + id], required_evidence: ['Result ' + id] })) };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  const sourceBytes = Buffer.from('\ufeffSynthetic specialist source\r\n');
  try {
    stop = await start(path.join(root, 'data'), port);
    const input = { planText: JSON.stringify(plan) + '\r\n', outcome: 'Source-backed brief', workspaceRoot: root, modelSelector: 'moongate/model',
      evidenceFiles: [{ name: 'facts.md', content_base64: sourceBytes.toString('base64'), task_ids: ['draft'] }] };
    const preview = await post('preview', input).then(response => response.json());
    const original = await post('create', { ...input, previewDigest: preview.execution_digest }).then(response => response.json());
    const delegated = await post('specialists', { id: original.id, taskId: 'draft', specialists: ['facts', 'alternatives'].map(task_id => ({ task_id, name: task_id, owner_id: 'reviewer', acceptance_criteria: ['Verify sources'], required_evidence: ['Notes'] })) }).then(response => response.json());
    const artifact = delegated.source.local_evidence.files[0].artifact_ref;
    const request = { id: delegated.id, executionDigest: delegated.execution_digest, taskId: 'facts', artifactRefs: [artifact], reason: 'Check original facts before integration' };
    for (const action of ['source-assignment-preview', 'source-assignment']) assert.equal((await post(action, request, 'https://untrusted.example')).status, 403);
    assert.equal((await post('source-assignment-preview', { ...request, artifactRefs: ['/tmp/private'] })).status, 400);
    assert.equal((await post('source-assignment-preview', { ...request, executionDigest: 'stale' })).status, 400);
    const proposedResponse = await post('source-assignment-preview', request); assert.equal(proposedResponse.status, 200); const proposed = await proposedResponse.json();
    assert.equal((await fetch(`${origin}/api/deliverables`).then(response => response.json())).deliverables.length, 2);
    assert.equal((await post('source-assignment', request)).status, 400);
    assert.equal((await post('source-assignment', { ...request, taskId: 'alternatives', previewDigest: proposed.execution_digest })).status, 400);
    const saved = await post('source-assignment', { ...request, previewDigest: proposed.execution_digest }); assert.equal(saved.status, 200); const child = await saved.json();
    assert.equal(child.status, 'awaiting_import'); assert.ok(child.graph.items.find(item => item.work_item_id === 'facts').input_artifacts.includes(artifact));
    assert.deepEqual(child.source.tasks, delegated.source.tasks);
    assert.equal((await post('prepare', { id: child.id })).status, 400);
    const served = await fetch(`${origin}/deliverable_panel.js`).then(response => response.text()); assert.match(served, /Assign source evidence to a task/);
    await stop(); stop = await start(path.join(root, 'data'), port);
    assert.equal((await post('source-assignment', { ...request, previewDigest: proposed.execution_digest }).then(response => response.json())).id, child.id);
    const boards = (await fetch(`${origin}/api/deliverables`).then(response => response.json())).deliverables;
    assert.equal(boards.length, 3); assert.deepEqual(boards.find(board => board.id === delegated.id).source, delegated.source);
    assert.deepEqual(await readFile(path.join(root, 'data/deliverables', child.id, artifact)), sourceBytes);
    assert.deepEqual(await readFile(path.join(root, 'data/deliverables', child.id, 'source-plan.json')), Buffer.from(input.planText));
    const brief = await post('delegation-brief', { id: child.id, executionDigest: child.execution_digest, ownerId: 'reviewer', includeSourceText: true }).then(response => response.json());
    assert.match(brief.text, /Source assignment history/); assert.match(brief.text, /Synthetic specialist source/);
    const next = { ...request, id: child.id, executionDigest: child.execution_digest, taskId: 'alternatives' };
    const nextPreview = await post('source-assignment-preview', next).then(response => response.json());
    for (const ref of ['runtime/prepare-intent.json', `.moonsuite/products/moonflow/runs/${child.id}/projection.json`]) {
      const file = path.join(root, 'data/deliverables', child.id, ref);
      await mkdir(path.dirname(file), { recursive: true }); await writeFile(file, 'null\n');
      for (const action of ['source-assignment-preview', 'source-assignment']) {
        const blocked = await post(action, { ...next, previewDigest: nextPreview.execution_digest });
        assert.equal(blocked.status, 400); assert.match((await blocked.json()).error, /pending native preparation/);
      }
      assert.equal((await readdir(path.join(root, 'data/deliverables'))).length, 3);
      assert.equal(await readFile(file, 'utf8'), 'null\n'); await rm(file);
    }
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('prerequisite HTTP preview/save/restart preserves exact source bytes and rejects stale/cyclic/cross-origin scope', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-prerequisites-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const tasks = ['research', 'draft', 'review', 'facts'];
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'prerequisite-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }],
    tasks: tasks.map((id, index) => ({ task_id: id, name: id, owner_id: 'writer', dependencies: index === 1 ? ['research'] : index === 2 ? ['draft'] : [], acceptance_gate_ids: [id] })),
    acceptance_gates: tasks.map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Check ' + id], required_evidence: ['Result ' + id] })) };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  const sourceBytes = Buffer.from('\ufeffFacts with original CRLF\r\n');
  try {
    stop = await start(path.join(root, 'data'), port);
    const input = { planText: JSON.stringify(plan) + '\r\n', outcome: 'Fact-checked brief', workspaceRoot: root, modelSelector: 'moongate/model',
      evidenceFiles: [{ name: 'facts.md', content_base64: sourceBytes.toString('base64'), task_ids: ['draft', 'facts'] }] };
    const initial = await post('preview', input).then(response => response.json());
    const parent = await post('create', { ...input, previewDigest: initial.execution_digest }).then(response => response.json());
    const request = { id: parent.id, executionDigest: parent.execution_digest, taskId: 'draft', dependencies: ['facts'], reason: 'Replace preliminary research with checked facts' };
    assert.equal((await post('prerequisites-preview', request, 'https://untrusted.example')).status, 403);
    assert.equal((await post('prerequisites', request, 'https://untrusted.example')).status, 403);
    assert.equal((await post('prerequisites-preview', { ...request, dependencies: ['review'] })).status, 400);
    assert.equal((await post('prerequisites-preview', { ...request, executionDigest: 'sha256:stale' })).status, 400);
    const previewResponse = await post('prerequisites-preview', request); assert.equal(previewResponse.status, 200);
    const preview = await previewResponse.json();
    assert.equal((await fetch(`${origin}/api/deliverables`).then(response => response.json())).deliverables.length, 1);
    assert.equal((await post('prerequisites', request)).status, 400);
    assert.equal((await post('prerequisites', { ...request, dependencies: [], previewDigest: preview.execution_digest })).status, 400);
    const savedResponse = await post('prerequisites', { ...request, previewDigest: preview.execution_digest }); assert.equal(savedResponse.status, 200);
    const child = await savedResponse.json(); assert.equal(child.status, 'awaiting_import');
    assert.deepEqual(child.graph.items.map(item => item.depends_on), [[], ['facts'], ['draft'], []]);
    assert.equal((await post('prepare', { id: child.id })).status, 400);
    const panel = await fetch(`${origin}/deliverable_panel.js`).then(response => response.text()); assert.match(panel, /Revise task prerequisites/);
    await stop(); stop = await start(path.join(root, 'data'), port);
    assert.equal((await post('prerequisites', { ...request, previewDigest: preview.execution_digest }).then(response => response.json())).id, child.id);
    const boards = (await fetch(`${origin}/api/deliverables`).then(response => response.json())).deliverables;
    assert.equal(boards.length, 2); assert.deepEqual(boards.find(board => board.id === parent.id).graph, parent.graph);
    const run = path.join(root, 'data/deliverables');
    assert.deepEqual(await readFile(path.join(run, child.id, 'source-plan.json')), Buffer.from(input.planText));
    assert.deepEqual(await readFile(path.join(run, child.id, child.source.local_evidence.files[0].artifact_ref)), sourceBytes);
    const brief = await post('delegation-brief', { id: child.id, executionDigest: child.execution_digest, ownerId: 'writer', includeSourceText: false }).then(response => response.json());
    assert.match(brief.text, /Prerequisite revision context/);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('operator HTTP route saves/reloads a local deliverable and refuses unavailable execution without inventing state', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-deliverable-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'synthetic-http-project' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'owner', display_name: 'Fixture owner' }], tasks: [{ task_id: 'draft', name: 'Write a brief', owner_id: 'owner', milestone_id: 'm1', dependencies: [], acceptance_gate_ids: ['g1'] }],
    acceptance_gates: [{ gate_id: 'g1', scope_type: 'task', scope_id: 'draft', criteria: ['Brief contains source notes'], required_evidence: ['Brief text'] }] };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  try {
    stop = await start(path.join(root, 'data'), port);
    const initial = await fetch(`${origin}/api/deliverables`).then(r => r.json()); assert.deepEqual(initial.deliverables, []);
    const payload = { planText: JSON.stringify(plan), outcome: 'Synthetic HTTP rehearsal brief', workspaceRoot: root, modelSelector: 'moongate/approved-model' };
    const denied = await post('create', payload, 'https://untrusted.example'); assert.equal(denied.status, 403);
    const created = await post('create', payload); assert.equal(created.status, 200); const board = await created.json(); assert.equal(board.status, 'awaiting_import');
    assert.equal((await post('create', payload).then(r => r.json())).id, board.id);
    const blocked = await post('prepare', { id: board.id }); assert.equal(blocked.status, 400); assert.match((await blocked.json()).error, /deliverable_review_file/);
    const html = await fetch(`${origin}/`).then(r => r.text()); assert.match(html, /deliverable_panel.js/);
    const script = await fetch(`${origin}/deliverable_panel.js`).then(r => r.text()); assert.match(script, /Delegate a deliverable/);
    await stop(); stop = await start(path.join(root, 'data'), port);
    const restored = await fetch(`${origin}/api/deliverables`).then(r => r.json()); assert.equal(restored.deliverables.length, 1); assert.equal(restored.deliverables[0].id, board.id); assert.equal(restored.deliverables[0].tasks[0].status, 'not_imported');
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('capacity HTTP proposal survives restart and binds explicit lane edges without rewriting the original', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-capacity-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'capacity-http-project' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }],
    tasks: ['first', 'second', 'third'].map(id => ({ task_id: id, name: id, owner_id: 'writer', milestone_id: 'm1', dependencies: [], acceptance_gate_ids: [id] })),
    acceptance_gates: ['first', 'second', 'third'].map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Sources checked'], required_evidence: ['Source notes'] })) };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  try {
    stop = await start(path.join(root, 'data'), port);
    const created = await post('create', { planText: JSON.stringify(plan), outcome: 'Three researched sections', workspaceRoot: root, modelSelector: 'moongate/approved-model' });
    const original = await created.json(); assert.equal(created.status, 200);
    const payload = { id: original.id, ownerLimits: { writer: 2 } };
    assert.equal((await post('capacity', payload, 'https://untrusted.example')).status, 403);
    const scoped = await post('capacity', payload), child = await scoped.json(); assert.equal(scoped.status, 200);
    assert.deepEqual(child.graph.items.map(i => i.depends_on), [[], [], ['first']]);
    assert.equal(child.source.capacity.parent_id, original.id);
    assert.equal((await post('capacity', payload).then(r => r.json())).id, child.id);
    assert.equal((await post('prepare', { id: child.id })).status, 400);
    await stop(); stop = await start(path.join(root, 'data'), port);
    const restored = await fetch(`${origin}/api/deliverables`).then(r => r.json());
    assert.equal(restored.deliverables.length, 2);
    assert.deepEqual(restored.deliverables.find(b => b.id === original.id).graph.items.map(i => i.depends_on), [[], [], []]);
    assert.deepEqual(restored.deliverables.find(b => b.id === child.id).graph.items.map(i => i.depends_on), [[], [], ['first']]);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('specialist HTTP proposals restart durably and preserve original plan bytes and scope', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-specialists-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'specialists-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }], tasks: [{ task_id: 'brief', name: 'Integrate brief', owner_id: 'writer', milestone_id: 'm1', dependencies: [], acceptance_gate_ids: ['g1'] }],
    acceptance_gates: [{ gate_id: 'g1', scope_type: 'task', scope_id: 'brief', criteria: ['Compare verified sources'], required_evidence: ['Final brief'] }] };
  const specs = ['facts', 'alternatives'].map(id => ({ task_id: id, name: id, owner_id: 'writer', acceptance_criteria: ['Inspect sources'], required_evidence: ['Source notes'] }));
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  try {
    stop = await start(path.join(root, 'data'), port);
    const original = await post('create', { planText: JSON.stringify(plan), outcome: 'Reviewed comparison brief', workspaceRoot: root, modelSelector: 'moongate/approved-model' }).then(r => r.json());
    const payload = { id: original.id, taskId: 'brief', specialists: specs };
    assert.equal((await post('specialists', payload, 'https://untrusted.example')).status, 403);
    assert.equal((await post('specialists', { ...payload, specialists: [] })).status, 400);
    const response = await post('specialists', payload), child = await response.json(); assert.equal(response.status, 200);
    assert.deepEqual(child.graph.items.map(i => i.depends_on), [[], [], ['facts', 'alternatives']]);
    assert.equal(child.source.specialists.integration_task_id, 'brief'); assert.equal(child.status, 'awaiting_import');
    assert.equal((await post('prepare', { id: child.id })).status, 400);
    const script = await fetch(`${origin}/deliverable_panel.js`).then(r => r.text()); assert.match(script, /Create specialist delegation/);
    await stop(); stop = await start(path.join(root, 'data'), port);
    assert.equal((await post('specialists', payload).then(r => r.json())).id, child.id);
    const boards = (await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables;
    assert.equal(boards.length, 2);
    assert.deepEqual(boards.find(b => b.id === original.id).graph, original.graph);
    assert.deepEqual(boards.find(b => b.id === child.id).source, child.source);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('R592 delegated capacity HTTP composition survives restart and preserves both parent scopes', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-delegated-capacity-http-'));
  const data = path.join(root, 'data'), port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'delegated-capacity-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }], tasks: [{ task_id: 'brief', name: 'Integrate brief', owner_id: 'writer', milestone_id: 'm1', dependencies: [], acceptance_gate_ids: ['g1'] }],
    acceptance_gates: [{ gate_id: 'g1', scope_type: 'task', scope_id: 'brief', criteria: ['Compare verified sources'], required_evidence: ['Final brief'] }] };
  const planText = JSON.stringify(plan, null, 3) + '\n';
  const specs = ['facts', 'alternatives', 'costs'].map(id => ({ task_id: id, name: id, owner_id: 'writer', acceptance_criteria: [`Review ${id}`], required_evidence: [`${id} notes`] }));
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  const bytes = (id, name) => readFile(path.join(data, 'deliverables', id, name), 'utf8');
  try {
    stop = await start(data, port);
    const created = await post('create', { planText, outcome: 'Capacity-planned comparison', workspaceRoot: root, modelSelector: 'moongate/approved-model' });
    assert.equal(created.status, 200); const original = await created.json();
    const split = await post('specialists', { id: original.id, taskId: 'brief', specialists: specs });
    assert.equal(split.status, 200); const delegated = await split.json();
    const originalBytes = await bytes(original.id, 'handoff.json'), delegatedBytes = await bytes(delegated.id, 'handoff.json');
    const payload = { id: delegated.id, ownerLimits: { writer: 1 } };
    assert.equal((await post('capacity', payload, 'https://untrusted.example')).status, 403);
    assert.equal((await post('capacity', { ...payload, ownerLimits: { writer: 0 } })).status, 400);
    assert.equal((await post('capacity', { ...payload, ownerLimits: { writer: 100 } })).status, 400);
    const response = await post('capacity', payload); assert.equal(response.status, 200); const scoped = await response.json();
    assert.equal(scoped.status, 'awaiting_import'); assert.ok(scoped.tasks.every(task => !task.dispatchable));
    assert.deepEqual(scoped.graph.items.map(i => i.depends_on), [[], ['facts'], ['alternatives'], ['facts', 'alternatives', 'costs']]);
    assert.deepEqual(scoped.source.specialists, delegated.source.specialists);
    assert.equal(scoped.source.capacity.parent_id, delegated.id);
    assert.equal(scoped.source.capacity.parent_execution_digest, delegated.execution_digest);
    assert.deepEqual(scoped.tasks.find(t => t.task_id === 'brief').acceptance_criteria, ['Compare verified sources']);
    assert.equal(await bytes(scoped.id, 'source-plan.json'), planText);
    assert.equal((await post('prepare', { id: scoped.id })).status, 400, 'no configured execution is invented');
    assert.equal((await post('capacity', { ...payload, id: scoped.id })).status, 400);
    const twoLanesResponse = await post('capacity', { ...payload, ownerLimits: { writer: 2 } });
    assert.equal(twoLanesResponse.status, 200); const twoLanes = await twoLanesResponse.json();
    assert.notEqual(twoLanes.id, scoped.id);
    assert.deepEqual(twoLanes.graph.items.map(i => i.depends_on), [[], [], ['facts'], ['facts', 'alternatives', 'costs']]);
    await stop(); stop = await start(data, port);
    assert.equal((await post('capacity', payload).then(r => r.json())).id, scoped.id);
    const boards = (await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables;
    assert.equal(boards.length, 4);
    assert.deepEqual(boards.find(b => b.id === scoped.id).source, scoped.source);
    for (const parent of [original, delegated]) assert.equal(boards.find(b => b.id === parent.id).status, 'awaiting_import');
    assert.equal(await bytes(original.id, 'handoff.json'), originalBytes);
    assert.equal(await bytes(delegated.id, 'handoff.json'), delegatedBytes);
    assert.equal(await bytes(original.id, 'source-plan.json'), planText);
    assert.equal(await bytes(delegated.id, 'source-plan.json'), planText);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('R606 HTTP evidence preview/save/restart/inspection is exact and rejects stale scope and undeclared reads', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-evidence-http-'));
  const data = path.join(root, 'data'), port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'evidence-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }], tasks: ['facts', 'brief'].map(id => ({ task_id: id, name: id, owner_id: 'writer', dependencies: [], acceptance_gate_ids: [id] })),
    acceptance_gates: ['facts', 'brief'].map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Inspect sources'], required_evidence: ['Source notes'] })) };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  const text = '\uFEFF{"original": "雪"}\r\n', planText = JSON.stringify(plan, null, 3) + '\n';
  const payload = { planText, outcome: 'Source-backed brief', workspaceRoot: root, modelSelector: 'moongate/approved-model', evidenceFiles: [{ name: 'facts.json', content_base64: Buffer.from(text).toString('base64'), task_ids: ['facts'] }] };
  try {
    stop = await start(data, port);
    assert.equal((await post('preview', payload, 'https://untrusted.example')).status, 403);
    assert.equal((await post('create', payload)).status, 400);
    const previewResponse = await post('preview', payload), preview = await previewResponse.json(); assert.equal(previewResponse.status, 200);
    assert.deepEqual((await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables, []);
    assert.equal((await post('create', { ...payload, outcome: 'Changed', previewDigest: preview.execution_digest })).status, 400);
    assert.equal((await post('preview', { ...payload, evidenceFiles: [{ ...payload.evidenceFiles[0], path: '/etc/passwd' }] })).status, 400);
    const response = await post('create', { ...payload, previewDigest: preview.execution_digest }), board = await response.json(); assert.equal(response.status, 200);
    const artifactRef = board.source.local_evidence.files[0].artifact_ref;
    assert.deepEqual(await readFile(path.join(data, 'deliverables', board.id, artifactRef)), Buffer.from(text));
    assert.equal(await readFile(path.join(data, 'deliverables', board.id, 'source-plan.json'), 'utf8'), planText);
    assert.ok(board.graph.items[0].input_artifacts.includes(artifactRef)); assert.ok(!board.graph.items[1].input_artifacts.includes(artifactRef));
    assert.equal((await post('inspect-evidence', { id: board.id, artifactRef }, 'https://untrusted.example')).status, 403);
    assert.equal((await post('inspect-evidence', { id: board.id, artifactRef: '../../etc/passwd' })).status, 400);
    assert.equal((await post('prepare', { id: board.id })).status, 400);
    await stop(); stop = await start(data, port);
    const restored = (await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables;
    assert.equal(restored.length, 1); assert.deepEqual(restored[0].source, board.source);
    const inspected = await post('inspect-evidence', { id: board.id, artifactRef }); assert.equal(inspected.status, 200); assert.equal((await inspected.json()).evidence.text, text);
    assert.equal((await post('create', { ...payload, previewDigest: preview.execution_digest }).then(r => r.json())).id, board.id);
    const script = await fetch(`${origin}/deliverable_panel.js`).then(r => r.text()); assert.match(script, /data-evidence-files/); assert.match(script, /Preview complete source\/task mapping/);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('R611 mounted task acceptance uses real HTTP preview/save, survives restart and cannot bypass changed preview or native review', async () => {
  const { mountDeliverablePanel } = await import('../frontend/opc_public/deliverable_panel.js');
  const { harness } = await import('./deliverable_panel_harness.mjs');
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-acceptance-http-'));
  const data = path.join(root, 'data'), port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop, dispose;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'acceptance-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false }, owners: [{ owner_id: 'writer', display_name: 'Writer' }],
    tasks: ['first', 'second'].map((task_id, i) => ({ task_id, name: 'Same visible name', owner_id: 'writer', milestone_id: 'm', dependencies: i ? ['first'] : [], acceptance_gate_ids: ['g'] })),
    acceptance_gates: [{ gate_id: 'g', scope_type: 'milestone', scope_id: 'm', criteria: ['Deliver complete milestone'], required_evidence: ['Milestone evidence'] }] };
  const post = (action, body) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: origin }, body: JSON.stringify(body) });
  let lastRequest;
  const fetcher = (url, options) => { if (options) lastRequest = { url, body: JSON.parse(options.body) }; return fetch(origin + url, options ? { ...options, headers: { ...options.headers, Origin: origin } } : undefined); };
  const settle = async h => { for (let i = 0; i < 100 && !h.host.innerHTML.includes('data-action="prepare"'); i++) await new Promise(resolve => setTimeout(resolve, 5)); };
  try {
    stop = await start(data, port);
    assert.equal((await fetch(`${origin}/deliverable_acceptance.js`)).status, 200);
    const h = harness(); dispose = mountDeliverablePanel(h.host, { fetcher });
    await new Promise(resolve => setTimeout(resolve, 20));
    const planText = JSON.stringify(plan, null, 2).replaceAll('\n', '\r\n') + '\r\n';
    await h.loadPlan([{ name: 'saved-native-plan.json', size: Buffer.byteLength(planText), arrayBuffer: async () => Buffer.from(planText) }]);
    h.input('outcome', 'Reviewed task-specific brief'); h.input('workspaceRoot', root); h.input('modelSelector', 'moongate/approved-model');
    await h.click('preview'); assert.equal(lastRequest, undefined); assert.match(h.host.innerHTML, /first needs explicit/);
    for (const id of ['first', 'second']) { h.acceptance(id, 'criteria', `Check ${id} source claims`); h.acceptance(id, 'evidence', `${id} source notes`); }
    await h.click('preview'); assert.match(h.host.innerHTML, /Exact task acceptance preview/);
    assert.deepEqual((await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables, []);
    await h.click('create'); const saved = structuredClone(lastRequest.body);
    let boards = (await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables; assert.equal(boards.length, 1);
    const board = boards[0]; assert.equal(board.status, 'awaiting_import'); assert.equal(await readFile(path.join(data, 'deliverables', board.id, 'source-plan.json'), 'utf8'), planText);
    const stale = structuredClone(saved); stale.taskCriteria.first.criteria = ['Changed after preview'];
    assert.equal((await post('create', stale)).status, 400);
    assert.equal((await post('create', { ...saved, taskCriteria: { first: saved.taskCriteria.first } })).status, 400);
    assert.equal((await post('create', { ...saved, taskCriteria: { ...saved.taskCriteria, missing: saved.taskCriteria.first } })).status, 400);
    dispose(); await stop(); stop = await start(data, port);
    assert.equal((await post('create', saved).then(r => r.json())).id, board.id);
    const reopened = harness(); dispose = mountDeliverablePanel(reopened.host, { fetcher }); await settle(reopened);
    assert.match(reopened.host.innerHTML, /Check first source claims/); assert.match(reopened.host.innerHTML, /Required evidence: second source notes/);
    await reopened.click('prepare'); assert.match(reopened.host.innerHTML, /deliverable_review_file/);
    boards = (await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables;
    assert.equal(boards.length, 1); assert.deepEqual(boards[0].graph.items.map(item => item.depends_on), [[], ['first']]); assert.ok(boards[0].tasks.every(task => task.status === 'not_imported' && !task.dispatchable));
  } finally { dispose?.(); if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});

test('owner handoff HTTP routes bind preview, preserve durable parent and reopen after host restart', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-owner-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'owner-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: Object.fromEntries(['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].map(k => [k, false])),
    owners: [{ owner_id: 'alex', display_name: 'Alex' }, { owner_id: 'bao', display_name: 'Bao' }],
    tasks: [{ task_id: 'draft', name: 'Draft', owner_id: 'alex', dependencies: [], acceptance_gate_ids: ['gate'] }],
    acceptance_gates: [{ gate_id: 'gate', scope_type: 'task', scope_id: 'draft', criteria: ['Source-backed draft'], required_evidence: ['Draft and notes'] }] };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  try {
    stop = await start(path.join(root, 'data'), port);
    const board = await post('create', { planText: JSON.stringify(plan), outcome: 'Draft for review', workspaceRoot: root, modelSelector: 'moongate/model' }).then(r => r.json());
    const body = { id: board.id, taskId: 'draft', ownerId: 'bao', reason: 'Alex is unavailable' };
    assert.equal((await post('owner-handoff-preview', body, 'https://untrusted.example')).status, 403);
    const previewResponse = await post('owner-handoff-preview', body); assert.equal(previewResponse.status, 200); const preview = await previewResponse.json();
    assert.equal(preview.source.tasks[0].owner_name, 'Bao');
    assert.equal((await post('owner-handoff', body)).status, 400);
    const savedResponse = await post('owner-handoff', { ...body, previewDigest: preview.execution_digest }); assert.equal(savedResponse.status, 200); const saved = await savedResponse.json();
    assert.equal(saved.status, 'awaiting_import'); assert.notEqual(saved.id, board.id);
    await stop(); stop = await start(path.join(root, 'data'), port);
    const boards = (await fetch(`${origin}/api/deliverables`).then(r => r.json())).deliverables;
    assert.equal(boards.length, 2); assert.equal(boards.find(b => b.id === board.id).tasks[0].owner_id, 'alex'); assert.equal(boards.find(b => b.id === saved.id).tasks[0].owner_id, 'bao');
    assert.equal((await post('prepare', { id: saved.id })).status, 400);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});


test('R630 real HTTP owner brief preview/download survives restart and rejects stale, cross-origin and damaged input without execution', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-brief-http-'));
  const port = await freePort(), origin = `http://127.0.0.1:${port}`;
  let stop;
  const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'brief-http' }, workflow: { status: 'pending_review', accepted: false },
    authority_effects: { spend_authorized: false, accounting_posted: false, payment_released: false, contract_signed: false, work_executed: false },
    owners: [{ owner_id: 'writer', display_name: 'Writer' }], tasks: [{ task_id: 'brief', name: 'Write briefing', owner_id: 'writer', dependencies: [], acceptance_gate_ids: ['g1'] }],
    acceptance_gates: [{ gate_id: 'g1', scope_type: 'task', scope_id: 'brief', criteria: ['Check source claims'], required_evidence: ['Source-backed brief'] }] };
  const post = (action, body, from = origin) => fetch(`${origin}/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: from }, body: JSON.stringify(body) });
  try {
    stop = await start(path.join(root, 'data'), port);
    const input = { planText: JSON.stringify(plan), outcome: 'A readable owner brief', workspaceRoot: root, modelSelector: 'moongate/approved-model', evidenceFiles: [{ name: 'facts.md', content_base64: Buffer.from('LOCAL SOURCE FACTS').toString('base64'), task_ids: ['brief'] }] };
    const proposal = await post('preview', input).then(response => response.json());
    const board = await post('create', { ...input, previewDigest: proposal.execution_digest }).then(response => response.json());
    const base = path.join(root, 'data/deliverables', board.id), filesBefore = (await readdir(base, { recursive: true })).sort();
    const body = { id: board.id, ownerId: 'writer', executionDigest: board.execution_digest, includeSourceText: false };
    assert.equal((await post('delegation-brief', body, 'https://untrusted.example')).status, 403);
    for (const extra of [{ ownerId: 'unknown' }, { executionDigest: 'stale' }, { includeSourceText: 'true' }, { packetDigest: 'stale' }]) assert.equal((await post('delegation-brief', { ...body, ...extra })).status, 400);
    const response = await post('delegation-brief', body); assert.equal(response.status, 200); const brief = await response.json();
    assert.match(brief.text, /Check source claims/); assert.doesNotMatch(brief.text, /LOCAL SOURCE FACTS|approved-model/); assert.equal(brief.source_text_included, false);
    const included = await post('delegation-brief', { ...body, includeSourceText: true }).then(response => response.json()); assert.match(included.text, /LOCAL SOURCE FACTS/);
    assert.equal((await post('delegation-brief', { ...body, includeSourceText: true, packetDigest: brief.content_digest })).status, 400);
    const js = await fetch(`${origin}/deliverable_panel.js`).then(response => response.text()); assert.match(js, /Prepare an owner delegation brief/);
    await stop(); stop = await start(path.join(root, 'data'), port);
    assert.deepEqual(await post('delegation-brief', { ...body, packetDigest: brief.content_digest }).then(response => response.json()), brief);
    assert.equal((await fetch(`${origin}/api/deliverables`).then(response => response.json())).deliverables.length, 1);
    assert.deepEqual((await readdir(base, { recursive: true })).sort(), filesBefore);
    assert.equal((await post('prepare', { id: board.id })).status, 400);
    await writeFile(path.join(base, board.source.local_evidence.files[0].artifact_ref), 'changed source');
    const damaged = await post('delegation-brief', { ...body, packetDigest: brief.content_digest }); assert.equal(damaged.status, 400); assert.match((await damaged.json()).error, /bytes changed/);
  } finally { if (stop) await stop(); await rm(root, { recursive: true, force: true }); }
});
