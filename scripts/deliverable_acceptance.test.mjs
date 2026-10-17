import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { acceptanceRows, acceptanceMap, inspectAcceptancePlan, readNativePlanFile } from '../frontend/opc_public/deliverable_acceptance.js';
import { mountDeliverablePanel } from '../frontend/opc_public/deliverable_panel.js';
import { compileDeliverable, json } from './deliverable_workflow.mjs';
import { createDeliverableHost } from './deliverable_host.mjs';
import { harness } from './deliverable_panel_harness.mjs';

const plan = () => ({ contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'acceptance-project' }, workflow: { status: 'pending_review', accepted: false },
  authority_effects: Object.fromEntries(['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].map(key => [key, false])),
  owners: [{ owner_id: 'writer', display_name: 'Writer' }], tasks: ['research', 'write'].map((id, i) => ({ task_id: id, name: 'Same name <unsafe>', owner_id: 'writer', milestone_id: 'm', dependencies: i ? ['research'] : [], acceptance_gate_ids: i ? ['project-gate'] : ['milestone-gate'] })),
  acceptance_gates: [{ gate_id: 'milestone-gate', scope_type: 'milestone', scope_id: 'm', criteria: ['Complete milestone <safely>'], required_evidence: ['Milestone report'] }, { gate_id: 'project-gate', scope_type: 'project', scope_id: 'acceptance-project', criteria: ['Review whole project'], required_evidence: ['Project report'] }] });
const time = '2026-10-12T18:30:00Z';
const asFile = (text, name = 'saved-plan.json') => ({ name, size: Buffer.byteLength(text), arrayBuffer: async () => Buffer.from(text) });
const tick = () => new Promise(resolve => setTimeout(resolve, 5));
const fillRows = h => { for (const id of ['research', 'write']) { h.acceptance(id, 'criteria', `Check ${id}\nVerify sources for ${id}`); h.acceptance(id, 'evidence', `${id} notes`); } };
async function fixture(run, intercept) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'moonproj-acceptance-'));
  const api = createDeliverableHost({ data: path.join(directory, 'data'), config: async () => ({}), readOperatorJson: async () => { throw Error('Unconfigured'); }, runMoonflow: async () => { throw Error('Execution forbidden'); }, now: () => time });
  const h = harness(), requests = [];
  const fetcher = async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await api.list() }) };
    const body = JSON.parse(options.body); requests.push({ url, body });
    try { return { ok: true, json: async () => await api.act(url.split('/').at(-1), body) }; }
    catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
  };
  // Resolve host errors before handing the response to the controller.
  const safeFetch = async (url, options) => {
    try { const response = await fetcher(url, options); const value = await response.json(); return { ...response, json: async () => value }; }
    catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
  };
  const disposers = [];
  const mount = (target = h) => { const dispose = mountDeliverablePanel(target.host, { fetcher: intercept ? (url, options) => intercept(url, options, safeFetch) : safeFetch }); disposers.push(dispose); return dispose; };
  const dispose = mount();
  const fill = () => { h.input('planText', json(plan())); h.input('outcome', 'Reviewed brief'); h.input('workspaceRoot', directory); h.input('modelSelector', 'moongate/model'); };
  try { await tick(); await run({ h, api, requests, directory, dispose, fill, mount }); }
  finally { disposers.forEach(dispose => dispose()); await rm(directory, { recursive: true, force: true }); }
}

test('R611 shared plan inspection exposes inherited scope without silently accepting it', () => {
  const rows = acceptanceRows(json(plan()));
  assert.deepEqual(rows.map(row => row.task_id), ['research', 'write']);
  assert.ok(rows.every(row => row.inherited && row.criteria === '' && row.evidence === ''));
  assert.equal(rows[0].owner_name, 'Writer'); assert.deepEqual(rows[1].dependencies, ['research']);
  assert.throws(() => acceptanceMap(rows), /research needs explicit/);
  rows.forEach(row => { row.criteria = `  Check ${row.task_id} \n\nSecond criterion`; row.evidence = `  ${row.task_id}.md  `; });
  const map = acceptanceMap(rows);
  assert.deepEqual(map.research, { criteria: ['Check research', 'Second criterion'], required_evidence: ['research.md'] });
  assert.notDeepEqual(map.research, map.write);
  for (const edit of [p => { p.tasks[1].task_id = 'research'; }, p => { p.tasks[0].dependencies = ['write']; }, p => { p.tasks[0].owner_id = 'missing'; }, p => { p.acceptance_gates[0].scope_id = 'wrong'; }, p => { p.workflow.accepted = true; }, p => { p.authority_effects.work_executed = true; }]) {
    const p = plan(); edit(p); assert.throws(() => inspectAcceptancePlan(json(p)));
  }
});

test('R611 unique task IDs remain safe for duplicate names and object prototype property names', () => {
  const p = plan(); p.tasks = ['__proto__', 'constructor', 'toString'].map(task_id => ({ ...p.tasks[0], task_id }));
  const rows = acceptanceRows(json(p)); rows.forEach(row => { row.criteria = `Check ${row.task_id}`; row.evidence = 'Notes'; });
  const map = acceptanceMap(rows);
  assert.equal(Object.getPrototypeOf(map), Object.prototype);
  assert.deepEqual(Object.keys(map), ['__proto__', 'constructor', 'toString']);
  const result = compileDeliverable({ planText: json(p), taskCriteria: map, outcome: 'Outcome', workspaceRoot: '/tmp/approved', modelSelector: 'moongate/model', recordedAt: time, artifactRoot: '/tmp/approved/data' });
  assert.deepEqual(result.source.tasks.map(task => task.acceptance_criteria[0]), ['Check __proto__', 'Check constructor', 'Check toString']);
  assert.throws(() => compileDeliverable({ planText: json(p), outcome: 'Outcome', workspaceRoot: '/tmp/approved', modelSelector: 'moongate/model', recordedAt: time, artifactRoot: '/tmp/approved/data' }), /Task-specific acceptance is required/);
});

test('R611 unchanged native task criteria retain whitespace and embedded line breaks exactly', () => {
  const p = plan(); p.tasks = [p.tasks[0]]; p.acceptance_gates[0] = { ...p.acceptance_gates[0], scope_type: 'task', scope_id: 'research', criteria: [' Check\nunchanged '], required_evidence: [' Notes\nfile '] };
  const rows = acceptanceRows(json(p)); assert.equal(rows[0].inherited, false);
  assert.deepEqual(acceptanceMap(rows).research, { criteria: [' Check\nunchanged '], required_evidence: [' Notes\nfile '] });
  rows[0].criteria = ' '; assert.throws(() => acceptanceMap(rows), /explicit acceptance/);
});

test('R611 saved plan reader preserves UTF-8/CRLF exact source and rejects invalid intake', async () => {
  const text = json(plan()).replaceAll('\n', '\r\n');
  assert.equal(await readNativePlanFile(asFile(text)), text);
  for (const file of [asFile(text, 'x.txt'), asFile(''), asFile('\uFEFF' + text), asFile('{}'), { name: 'x.json', size: 1048577 }, { name: 'x.json', size: 1, arrayBuffer: async () => Buffer.from([255]) }, { name: 'x.json', size: 1, arrayBuffer: async () => Buffer.from('{}') }]) await assert.rejects(() => readNativePlanFile(file));
});

test('R611 mounted forms load saved plan, require task acceptance, preview exact board, save, reopen and retain review boundary', () => fixture(async f => {
  f.fill(); await f.h.loadPlan([asFile(json(plan()))]);
  assert.doesNotMatch(f.h.host.innerHTML, /Task-specific acceptance JSON/);
  assert.match(f.h.host.innerHTML, /milestone m · inherited context/); assert.match(f.h.host.innerHTML, /project acceptance-project · inherited context/);
  assert.match(f.h.host.innerHTML, /Same name &lt;unsafe&gt; \(research\)/); assert.doesNotMatch(f.h.host.innerHTML, /Same name <unsafe>/);
  await f.h.click('preview'); assert.equal(f.requests.length, 0); assert.match(f.h.host.innerHTML, /research needs explicit/);
  fillRows(f.h); await f.h.click('create'); assert.equal(f.requests.length, 0); assert.match(f.h.host.innerHTML, /Preview the complete/);
  await f.h.click('preview'); assert.deepEqual(await f.api.list(), []); assert.match(f.h.host.innerHTML, /Exact task acceptance preview/); assert.match(f.h.host.innerHTML, /Required outputs: research notes/); assert.match(f.h.host.innerHTML, /Complete proposed task graph/);
  const preview = f.requests.at(-1).body;
  await f.h.click('create'); const [board] = await f.api.list(); assert.equal(board.status, 'awaiting_import');
  assert.deepEqual(board.source.tasks.map(task => task.acceptance_criteria), [['Check research', 'Verify sources for research'], ['Check write', 'Verify sources for write']]);
  assert.deepEqual(board.graph.items.map(task => task.depends_on), [[], ['research']]);
  assert.equal(await readFile(path.join(f.directory, 'data/deliverables', board.id, 'source-plan.json'), 'utf8'), preview.planText);
  await f.h.click('create'); assert.equal((await f.api.list()).length, 1);
  f.dispose(); const reopened = harness(); f.mount(reopened); await tick(); assert.match(reopened.host.innerHTML, /Check research/); assert.match(reopened.host.innerHTML, /Required evidence: write notes/);
  await reopened.click('prepare'); assert.match(reopened.host.innerHTML, /deliverable_review_file/); assert.equal((await f.api.list())[0].status, 'awaiting_import');
}));

test('R611 mounted edits invalidate previews; stale task and source controls cannot edit a replacement plan', () => fixture(async f => {
  f.fill(); fillRows(f.h); await f.h.click('preview');
  const stale = f.h.host.querySelectorAll('[data-acceptance-field]')[0];
  f.h.acceptance('research', 'criteria', 'Updated research'); assert.ok(f.h.get('[data-action="create"]').disabled);
  const count = f.requests.length; await f.h.click('create'); assert.equal(f.requests.length, count);
  await f.h.click('preview');
  const p = plan(); p.tasks[0].name = 'Replacement scope';
  f.h.input('planText', json(p)); stale.value = 'Stale acceptance'; stale.events.input({ target: stale });
  await f.h.click('preview'); assert.match(f.h.host.innerHTML, /research needs explicit/);
  fillRows(f.h); await f.h.click('preview');
  for (const [field, value] of [['outcome', 'Changed'], ['workspaceRoot', f.directory + '/other'], ['modelSelector', 'moongate/other']]) {
    f.h.input(field, value); assert.ok(f.h.get('[data-action="create"]').disabled); await f.h.click('preview');
  }
  await f.h.click('cancel-draft'); assert.equal(f.h.get('[data-field="planText"]').value, ''); assert.equal(f.h.host.querySelectorAll('[data-acceptance-field]').length, 0); assert.deepEqual(await f.api.list(), []);
}));

test('R611 failed saved-plan replacement preserves edited acceptance and picker cancellation is a no-op', () => fixture(async f => {
  f.fill(); fillRows(f.h); await f.h.loadPlan([]); await f.h.loadPlan([asFile('{}')]);
  assert.match(f.h.host.innerHTML, /Check research/); assert.match(f.h.host.innerHTML, /native review-pending/);
  await f.h.click('preview'); assert.equal(f.requests.length, 1);
}));

test('R611 cancel and repeated clicks isolate a late preview from a new draft', async () => {
  let release, calls = 0; const pending = new Promise(resolve => { release = resolve; });
  await fixture(async f => {
    f.fill(); fillRows(f.h); const first = f.h.click('preview'); await f.h.click('preview'); assert.equal(calls, 1);
    await f.h.click('cancel-draft'); f.fill(); fillRows(f.h); f.h.input('outcome', 'New scope'); await f.h.click('preview');
    assert.match(f.h.host.innerHTML, /Outcome: New scope/); release(); await first;
    assert.match(f.h.host.innerHTML, /Outcome: New scope/); assert.deepEqual(await f.api.list(), []);
    await f.h.click('create'); assert.equal((await f.api.list())[0].outcome, 'New scope');
  }, async (url, options, next) => { if (url.endsWith('/preview') && ++calls === 1) await pending; return next(url, options); });
});

test('R611 cancelled or disposed late file reads cannot restore discarded task forms', () => fixture(async f => {
  f.fill(); let release; const pending = new Promise(resolve => { release = resolve; }), text = json(plan());
  const read = f.h.loadPlan([{ name: 'late.json', size: Buffer.byteLength(text), arrayBuffer: () => pending }]);
  await f.h.click('cancel-draft'); release(Buffer.from(text)); await read;
  assert.equal(f.h.get('[data-field="planText"]').value, ''); assert.equal(f.h.host.querySelectorAll('[data-acceptance-field]').length, 0);
  let releaseAgain; const late = new Promise(resolve => { releaseAgain = resolve; });
  const again = f.h.loadPlan([{ name: 'late.json', size: Buffer.byteLength(text), arrayBuffer: () => late }]);
  const before = f.h.host.innerHTML; f.dispose(); releaseAgain(Buffer.from(text)); await again; assert.equal(f.h.host.innerHTML, before);
}));

test('R611 repeated save clicks serialize and cancellation cannot misrepresent an in-flight save', async () => {
  let release, saves = 0; const pending = new Promise(resolve => { release = resolve; });
  await fixture(async f => {
    f.fill(); fillRows(f.h); await f.h.click('preview');
    const first = f.h.click('create'); await f.h.click('create'); assert.equal(saves, 1);
    assert.ok(f.h.get('[data-action="cancel-draft"]').disabled); await f.h.click('cancel-draft');
    assert.notEqual(f.h.get('[data-field="planText"]').value, '');
    release(); await first; assert.equal((await f.api.list()).length, 1); assert.match(f.h.host.innerHTML, /Task board saved/);
  }, async (url, options, next) => { if (url.endsWith('/create')) { saves++; await pending; } return next(url, options); });
});

test('R611 frontend packaging includes the shared module used by the production panel', async () => {
  const build = await readFile(new URL('./build_opc_frontend.sh', import.meta.url), 'utf8');
  assert.match(build, /cp "\$ROOT\/frontend\/opc_public\/deliverable_acceptance\.js" "\$DIST\/deliverable_acceptance\.js"/);
});

test('R611 oversize combined request fails before network and keeps the task draft repairable', () => fixture(async f => {
  f.fill(); fillRows(f.h);
  const large = plan(); large.unused_native_context = 'x'.repeat(1000000);
  f.h.input('planText', json(large)); fillRows(f.h);
  await f.h.click('preview'); assert.equal(f.requests.length, 0); assert.match(f.h.host.innerHTML, /host request limit/);
  f.h.input('planText', json(plan())); fillRows(f.h); await f.h.click('preview'); assert.equal(f.requests.length, 1);
}));
