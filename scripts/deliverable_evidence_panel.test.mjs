import { harness } from './deliverable_panel_harness.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { compileDeliverable, json } from './deliverable_workflow.mjs';
import { createDeliverableHost } from './deliverable_host.mjs';
import { mountDeliverablePanel, readEvidenceFiles } from '../frontend/opc_public/deliverable_panel.js';

const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'evidence-compat' }, workflow: { status: 'pending_review', accepted: false }, authority_effects: Object.fromEntries(['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].map(k => [k, false])), owners: [{ owner_id: 'a', display_name: 'A' }], tasks: [{ task_id: 't', name: 'Task', owner_id: 'a', dependencies: [], acceptance_gate_ids: ['g'] }], acceptance_gates: [{ gate_id: 'g', scope_type: 'task', scope_id: 't', criteria: ['Check'], required_evidence: ['Notes'] }] };
const time = '2026-10-12T09:00:00Z';
const file = (name = 'source.md', text = '\uFEFF# Source\r\n<script>source only</script>\r\n') => { const bytes = Buffer.from(text); return { name, size: bytes.length, arrayBuffer: async () => bytes }; };
const tick = () => new Promise(resolve => setTimeout(resolve, 5));

async function fixture(run, fetchOverride) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'moonproj-evidence-panel-'));
  const api = createDeliverableHost({ data: path.join(directory, 'data'), config: async () => ({}), readOperatorJson: async () => { throw Error('Unconfigured'); }, runMoonflow: async () => { throw Error('Native execution forbidden in panel test'); }, now: () => time });
  const h = harness(), requests = [];
  const fetcher = async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await api.list() }) };
    requests.push({ url, body: JSON.parse(options.body) });
    try { const value = await api.act(url.split('/').at(-1), JSON.parse(options.body)); return { ok: true, json: async () => value }; }
    catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
  };
  const dispose = mountDeliverablePanel(h.host, { fetcher: fetchOverride ? (url, options) => fetchOverride(url, options, fetcher) : fetcher });
  const fill = () => { h.input('planText', json(plan)); h.input('outcome', 'Outcome'); h.input('workspaceRoot', directory); h.input('modelSelector', 'moongate/model'); };
  try { await tick(); await run({ h, api, requests, directory, dispose, fill }); } finally { dispose(); await rm(directory, { recursive: true, force: true }); }
}

test('R606 empty evidence retains the exact pre-feature golden execution identity', () => {
  const options = { planText: json(plan), outcome: 'Outcome', workspaceRoot: '/tmp/w', modelSelector: 'moongate/model', artifactRoot: '/tmp/w/data/deliverables', recordedAt: time };
  for (const evidenceFiles of [undefined, []]) {
    const h = compileDeliverable({ ...options, evidenceFiles });
    assert.equal(h.execution_digest, 'sha256:bb4938562e3163ba67442b32d578f2e6146d152fbe782fc0658a7eac089490e3');
    assert.equal(Object.hasOwn(h.source, 'local_evidence'), false);
  }
});

test('R606 browser file reader preserves BOM/CRLF/non-ASCII raw bytes and rejects binary, oversized or invalid UTF-8 sources', async () => {
  const input = file('客户.csv', '\uFEFFname,value\r\n雪,1\r\n'), [read] = await readEvidenceFiles([input]);
  assert.deepEqual(Buffer.from(read.content_base64, 'base64'), await input.arrayBuffer());
  assert.equal(read.text, '\uFEFFname,value\r\n雪,1\r\n'); assert.equal(read.inspected, false);
  for (const input of [file('file.exe'), file('x.txt', '\0'), { name: 'x.md', size: 1, arrayBuffer: async () => Buffer.from([255]) }, { name: 'x.md', size: 131073, arrayBuffer: async () => { throw Error('Must reject before reading'); } }]) await assert.rejects(() => readEvidenceFiles([input]));
  await assert.rejects(() => readEvidenceFiles([file(), file()]), /unique/);
});

test('R606 mounted intake inspects exact content, assigns named tasks, previews, saves and reinspects', () => fixture(async f => {
  f.fill(); await f.h.upload([file()]);
  assert.match(f.h.host.innerHTML, /&lt;script&gt;source only&lt;\/script&gt;/); assert.doesNotMatch(f.h.host.innerHTML, /<script>source only/);
  assert.ok(f.h.get('[data-action="create"]').disabled);
  await f.h.click('preview'); assert.equal(f.requests.length, 0); assert.match(f.h.host.innerHTML, /Inspect each source/);
  f.h.check('[data-evidence-inspected="0"]'); f.h.check('[data-evidence-task="t"]');
  await f.h.click('preview'); assert.equal(f.requests.at(-1).url, '/api/deliverables/preview'); assert.equal((await f.api.list()).length, 0);
  assert.match(f.h.host.innerHTML, /Exact evidence delegation preview/); assert.match(f.h.host.innerHTML, /Task<\/strong> \(t\)/);
  assert.equal(f.h.get('[data-action="create"]').disabled, false);
  await f.h.click('create'); assert.equal((await f.api.list()).length, 1); assert.match(f.h.host.innerHTML, /Saved local source\/task mapping/);
  assert.equal(f.requests.at(-1).body.evidenceFiles[0].content_base64, (await file().arrayBuffer()).toString('base64'));
  await f.h.click('inspect-evidence'); assert.match(f.h.host.innerHTML, /Saved source: source.md/);
}));

test('R606 mounted changed plan, source mapping or form data invalidates preview; stale detached controls cannot submit', () => fixture(async f => {
  f.fill(); await f.h.upload([file()]); f.h.check('[data-evidence-inspected="0"]'); f.h.check('[data-evidence-task="t"]'); await f.h.click('preview');
  const stalePreview = f.h.get('[data-action="preview"]'), staleMapping = f.h.get('[data-evidence-task="t"]');
  f.h.input('outcome', 'Changed outcome'); assert.equal(f.h.get('[data-action="create"]').disabled, true);
  const count = f.requests.length; await f.h.click('create'); assert.equal(f.requests.length, count); assert.match(f.h.host.innerHTML, /Preview the complete/);
  staleMapping.checked = false; staleMapping.events.change({ target: staleMapping }); await stalePreview.events.click(); assert.equal(f.requests.length, count);
  await f.h.click('preview'); assert.equal(f.requests.length, count + 1);
  f.h.check('[data-evidence-task="t"]', false); await f.h.click('create'); assert.equal(f.requests.length, count + 1);
  f.h.check('[data-evidence-task="t"]'); await f.h.click('preview');
  f.h.input('planText', json({ ...plan, tasks: [{ ...plan.tasks[0], task_id: 'changed' }] }));
  await f.h.click('preview'); assert.equal((await f.api.list()).length, 0); assert.match(f.h.host.innerHTML, /Unresolved acceptance|existing task/);
}));

test('R606 mounted failed replacement preserves prior bytes and removal retains no-evidence preview and creation', () => fixture(async f => {
  f.fill(); await f.h.upload([file()]); await f.h.upload([file('bad.exe')]);
  assert.match(f.h.host.innerHTML, /source.md/); assert.match(f.h.host.innerHTML, /unique TXT/);
  await f.h.click('evidence-remove'); assert.equal(f.h.get('[data-action="create"]').disabled, true);
  await f.h.click('preview'); await f.h.click('create'); const boards = await f.api.list(); assert.equal(boards.length, 1); assert.equal(boards[0].source.local_evidence, undefined);
}));

test('R606 mounted repeated previews serialize and late preview cannot redraw disposed panel', async () => {
  let release, posts = 0; const pending = new Promise(resolve => { release = resolve; });
  await fixture(async f => {
    f.fill(); await f.h.upload([file()]); f.h.check('[data-evidence-inspected="0"]'); f.h.check('[data-evidence-task="t"]');
    const first = f.h.click('preview'); await f.h.click('preview'); assert.equal(posts, 1);
    const before = f.h.host.innerHTML; f.dispose(); release(); await first;
    assert.equal(f.h.host.innerHTML, before); assert.deepEqual(await f.api.list(), []);
  }, async (url, options, next) => { if (options) { posts++; await pending; } return next(url, options); });
});

test('R606 dismissed intake ignores a late asynchronous file read', () => fixture(async f => {
  f.fill(); let release; const pending = new Promise(resolve => { release = resolve; });
  const read = f.h.upload([{ name: 'later.txt', size: 1, arrayBuffer: () => pending }]);
  const before = f.h.host.innerHTML; f.dispose(); release(Buffer.from('x')); await read;
  assert.equal(f.h.host.innerHTML, before); assert.equal(f.requests.length, 0);
}));
