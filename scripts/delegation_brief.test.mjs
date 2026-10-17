import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile, readdir, symlink } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createDeliverableHost } from './deliverable_host.mjs';
import { json, sha } from './deliverable_workflow.mjs';
import { mountDeliverablePanel } from '../frontend/opc_public/deliverable_panel.js';
import { harness } from './deliverable_panel_harness.mjs';

const now = '2026-10-13T02:00:00Z';
const plan = { contract_id: 'moonproj.project-plan-artifact.v1', project: { project_id: 'brief-fixture' }, workflow: { status: 'pending_review', accepted: false },
  authority_effects: Object.fromEntries(['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].map(key => [key, false])),
  owners: [{ owner_id: 'a', display_name: 'Alex' }, { owner_id: 'b', display_name: 'Bao' }],
  tasks: ['first', 'second', 'third'].map((id, index) => ({ task_id: id, name: index === 0 ? '<script>Source [check](javascript:bad)</script>' : id, owner_id: index === 1 ? 'b' : 'a', dependencies: index === 1 ? ['first'] : [], acceptance_gate_ids: [id] })),
  acceptance_gates: ['first', 'second', 'third'].map(id => ({ gate_id: id, scope_type: 'task', scope_id: id, criteria: ['Check ' + id], required_evidence: ['Evidence ' + id] })) };
const textA = '\ufeffOriginal source\r\n```\n</textarea><script>bad()</script>\n`````\n';
const evidenceFiles = [{ name: 'source.md', content_base64: Buffer.from(textA).toString('base64'), task_ids: ['first', 'third'] }, { name: 'other.md', content_base64: Buffer.from('OTHER OWNER SOURCE ONLY').toString('base64'), task_ids: ['second'] }];
const input = root => ({ planText: json(plan), outcome: 'Compare local sources', workspaceRoot: root, modelSelector: 'moongate/private-model', evidenceFiles });
const request = (board, extra = {}) => ({ id: board.id, ownerId: 'a', executionDigest: board.execution_digest, includeSourceText: false, ...extra });
async function fixture(run) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'delegation-brief-'));
  const options = { data: path.join(root, 'data'), config: async () => { throw Error('Brief must not read execution configuration'); }, readOperatorJson: async () => { throw Error('Brief must not read operator files'); }, runMoonflow: async () => { throw Error('Brief must not call native runtime'); }, now: () => now };
  const api = createDeliverableHost(options);
  try { const value = input(root), preview = await api.act('preview', value); const board = await api.act('create', { ...value, previewDigest: preview.execution_digest }); await run({ root, api, board, options }); }
  finally { await rm(root, { recursive: true, force: true }); }
}
async function snapshot(root) {
  const entries = await readdir(root, { recursive: true, withFileTypes: true });
  return Object.fromEntries(await Promise.all(entries.filter(entry => entry.isFile()).map(async entry => { const file = path.join(entry.parentPath, entry.name); return [path.relative(root, file), sha(await readFile(file))]; })));
}
const select = (h, selector, value) => { const node = h.get(selector); node.value = value; node.events.change({ target: node }); };
const settle = () => new Promise(resolve => setTimeout(resolve, 15));
function mounted(api, extension = {}) {
  const h = harness(), downloads = [], calls = [];
  const fetcher = async (url, options) => {
    if (!options) return { ok: true, json: async () => ({ deliverables: await api.list() }) };
    const body = JSON.parse(options.body); calls.push(body);
    try { const value = await api.act(url.split('/').at(-1), body); await extension.delay?.(body); return { ok: true, json: async () => value }; }
    catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
  };
  return { h, downloads, calls, dispose: mountDeliverablePanel(h.host, { fetcher, download: (text, filename) => downloads.push({ text, filename }) }) };
}

test('owner brief is a readable no-write exact-scope handoff with dependency owners, acceptance and downstream context', () => fixture(async ({ root, api, board, options }) => {
  const before = await snapshot(root), brief = await api.act('delegation-brief', request(board));
  assert.deepEqual(brief.task_ids, ['first', 'third']); assert.equal(brief.source_text_included, false); assert.equal(brief.content_digest, sha(brief.text));
  assert.match(brief.text, /Check first/); assert.match(brief.text, /Evidence third/); assert.match(brief.text, /second \(second\), Bao \(b\)/);
  assert.doesNotMatch(brief.text, /Check second|OTHER OWNER SOURCE ONLY|Original source|private-model/);
  assert.ok(!brief.text.includes(root)); assert.match(brief.text, /not a current execution-status report/); assert.match(brief.text, /No work starts/);
  assert.doesNotMatch(brief.text, /<script>/); assert.ok(brief.text.includes('\\<script\\>'));
  const next = createDeliverableHost(options); assert.deepEqual(await next.act('delegation-brief', { ...request(board), packetDigest: brief.content_digest }), brief);
  assert.deepEqual(await snapshot(root), before); assert.equal((await next.list()).length, 1);
  const ownerB = await api.act('delegation-brief', request(board, { ownerId: 'b' }));
  assert.match(ownerB.text, /Wait for named acceptance of:[\s\S]*Alex \(a\)/); assert.doesNotMatch(ownerB.text, /Check first/);
}));

test('explicit opt-in includes only assigned full source bytes once, safely fenced, and changes packet digest', () => fixture(async ({ api, board }) => {
  const excluded = await api.act('delegation-brief', request(board));
  const included = await api.act('delegation-brief', request(board, { includeSourceText: true }));
  assert.notEqual(excluded.content_digest, included.content_digest); assert.equal(included.text.split(textA).length, 2);
  assert.match(included.text, /``````text/); assert.doesNotMatch(included.text, /OTHER OWNER SOURCE ONLY/);
  assert.equal(included.source_refs.length, 1);
  await assert.rejects(() => api.act('delegation-brief', { ...request(board, { includeSourceText: true }), packetDigest: excluded.content_digest }), /Preview this exact owner brief/);
}));

test('invalid owner, missing boolean, stale board and stale packet fail without creating work', () => fixture(async ({ root, api, board }) => {
  const before = await snapshot(root);
  for (const extra of [{ ownerId: '' }, { ownerId: '../a' }, { ownerId: 'absent' }, { ownerId: '__proto__' }, { includeSourceText: 'true' }, { includeSourceText: undefined }, { executionDigest: 'sha256:stale' }, { packetDigest: 'sha256:stale' }]) await assert.rejects(() => api.act('delegation-brief', request(board, extra)));
  assert.deepEqual(await snapshot(root), before);
}));

test('export verifies exact native plan and all saved evidence, including reference-only and download requests', () => fixture(async ({ root, api, board }) => {
  const base = path.join(root, 'data/deliverables', board.id), file = path.join(base, board.source.local_evidence.files[0].artifact_ref);
  const brief = await api.act('delegation-brief', request(board));
  await writeFile(file, 'changed'); await assert.rejects(() => api.act('delegation-brief', { ...request(board), packetDigest: brief.content_digest }), /bytes changed/);
  await rm(file); await assert.rejects(() => api.act('delegation-brief', request(board)), /ENOENT/);
  const outside = path.join(root, 'outside.md'); await writeFile(outside, textA); await symlink(outside, file);
  await assert.rejects(() => api.act('delegation-brief', request(board)), /symlink/);
  await rm(file); await writeFile(file, textA); await writeFile(path.join(base, 'source-plan.json'), json(plan) + ' ');
  await assert.rejects(() => api.act('delegation-brief', request(board)), /Source plan bytes changed/);
}));

test('reassigned owner, specialist integration and capacity composition export the current scope and retained provenance', () => fixture(async ({ api, board }) => {
  const change = { id: board.id, taskId: 'first', ownerId: 'b', reason: 'Coverage while Alex is away' };
  const preview = await api.act('owner-handoff-preview', change), reassigned = await api.act('owner-handoff', { ...change, previewDigest: preview.execution_digest });
  const delegated = await api.act('specialists', { id: reassigned.id, taskId: 'second', specialists: ['facts', 'writing'].map(task_id => ({ task_id, name: task_id, owner_id: 'b', acceptance_criteria: ['Review contribution'], required_evidence: ['Contribution notes'] })) });
  const capacity = await api.act('capacity', { id: delegated.id, ownerLimits: { a: 1, b: 1 } });
  const brief = await api.act('delegation-brief', request(capacity, { ownerId: 'b', includeSourceText: true }));
  assert.deepEqual(brief.task_ids, ['first', 'facts', 'writing', 'second']); assert.match(brief.text, /Alex \(a\) → Bao \(b\)/);
  assert.match(brief.text, /Coverage while Alex is away/); assert.match(brief.text, /Specialist integration boundary/); assert.match(brief.text, /Owner capacity lanes/);
  assert.ok(brief.text.includes(delegated.id)); assert.ok(brief.text.includes(capacity.execution_digest));
  assert.match(brief.text, /No local source files assigned/); assert.ok(brief.text.includes(textA));
  assert.equal((await api.state(board.id)).source.tasks[0].owner_id, 'a');
}));

test('mounted owner selection previews, explicit source opt-in invalidates, and download reverifies exact bytes', () => fixture(async ({ api, board }) => {
  const m = mounted(api), { h } = m;
  try { await settle(); assert.equal(h.get('[data-action="brief-preview"]').disabled, true); select(h, '[data-brief-owner]', 'a');
    await h.click('brief-preview'); assert.equal(h.get('[data-action="brief-download"]').disabled, false); assert.match(h.host.innerHTML, /Source text excluded/);
    const detached = h.get('[data-action="brief-download"]'); h.check('[data-brief-source]'); assert.equal(h.get('[data-action="brief-download"]').disabled, true);
    await detached.events.click(); await h.click('brief-download'); assert.equal(m.downloads.length, 0);
    await h.click('brief-preview'); assert.match(h.host.innerHTML, /Source text included/); assert.ok(h.host.innerHTML.includes('&lt;/textarea&gt;&lt;script&gt;'));
    await h.click('brief-download'); assert.equal(m.downloads.length, 1); assert.ok(m.downloads[0].text.includes(textA));
    assert.equal(m.calls.at(-1).packetDigest, sha(m.downloads[0].text)); assert.equal(m.calls.at(-1).executionDigest, board.execution_digest);
    await h.click('brief-download'); assert.equal(m.downloads.length, 2); assert.deepEqual(m.downloads[0], m.downloads[1]);
    await h.click('refresh'); assert.equal(h.get('[data-action="brief-download"]').disabled, true); assert.equal(h.get('[data-brief-source]').checked, false);
    assert.equal((await api.list()).length, 1);
  } finally { m.dispose(); }
}));

test('mounted repeated preview, cancel, stale selection and disposal cannot restore or download a late packet', () => fixture(async ({ api }) => {
  let release; const delayed = new Promise(resolve => { release = resolve; });
  const m = mounted(api, { delay: () => delayed }), { h } = m;
  try { await settle(); select(h, '[data-brief-owner]', 'a'); const button = h.get('[data-action="brief-preview"]');
    const pending = button.events.click(); await button.events.click(); assert.equal(m.calls.length, 1);
    await h.click('brief-cancel'); select(h, '[data-brief-owner]', 'b'); release(); await pending;
    assert.equal(h.get('[data-action="brief-download"]').disabled, true); assert.doesNotMatch(h.host.innerHTML, /Owner brief ready to inspect/);
    await h.click('brief-preview'); const oldDownload = h.get('[data-action="brief-download"]'); await h.click('brief-cancel'); await oldDownload.events.click(); assert.equal(m.downloads.length, 0);
    assert.equal(h.get('[data-brief-source]').checked, false);
  } finally { release(); m.dispose(); }
  let finish; const wait = new Promise(resolve => { finish = resolve; }); const disposed = mounted(api, { delay: () => wait });
  await settle(); select(disposed.h, '[data-brief-owner]', 'a'); const pending = disposed.h.click('brief-preview'); const html = disposed.h.host.innerHTML;
  disposed.dispose(); finish(); await pending; assert.equal(disposed.h.host.innerHTML, html); assert.equal(disposed.downloads.length, 0);
}));

test('mounted cancelled download never creates a file and changed saved bytes clear preview with repairable error', () => fixture(async ({ root, api, board }) => {
  let release; const delayed = new Promise(resolve => { release = resolve; }); const m = mounted(api, { delay: body => body.packetDigest ? delayed : undefined });
  try { await settle(); select(m.h, '[data-brief-owner]', 'a'); await m.h.click('brief-preview'); const pending = m.h.click('brief-download');
    await m.h.click('brief-cancel'); release(); await pending; assert.equal(m.downloads.length, 0);
    select(m.h, '[data-brief-owner]', 'a'); await m.h.click('brief-preview');
    await writeFile(path.join(root, 'data/deliverables', board.id, board.source.local_evidence.files[0].artifact_ref), 'tampered');
    await m.h.click('brief-download'); assert.equal(m.downloads.length, 0); assert.match(m.h.host.innerHTML, /bytes changed/); assert.equal(m.h.get('[data-action="brief-download"]').disabled, true);
  } finally { release(); m.dispose(); }
}));

test('actual browser download adapter creates exact UTF-8 Markdown Blob, safe filename and revokes temporary URL', () => fixture(async ({ api }) => {
  const h = harness(), blobs = [], clicks = [], revoked = [];
  const oldDocument = globalThis.document, oldCreate = URL.createObjectURL, oldRevoke = URL.revokeObjectURL;
  globalThis.document = { createElement(tag) { assert.equal(tag, 'a'); return { click() { clicks.push({ href: this.href, filename: this.download }); } }; } };
  URL.createObjectURL = blob => { blobs.push(blob); return 'blob:local-brief'; }; URL.revokeObjectURL = url => revoked.push(url);
  const fetcher = async (url, options) => ({ ok: true, json: async () => options ? api.act(url.split('/').at(-1), JSON.parse(options.body)) : { deliverables: await api.list() } });
  const dispose = mountDeliverablePanel(h.host, { fetcher });
  try { await settle(); select(h, '[data-brief-owner]', 'a'); assert.match(h.host.innerHTML, /<details open><summary>Prepare an owner delegation brief/);
    h.check('[data-brief-source]'); await h.click('brief-preview'); await h.click('brief-download'); await settle();
    assert.equal(blobs.length, 1); assert.equal(blobs[0].type, 'text/markdown;charset=utf-8'); assert.ok((await blobs[0].text()).includes(textA));
    assert.match(clicks[0].filename, /^deliverable-[a-f0-9]{24}-a-[a-f0-9]{12}-brief\.md$/); assert.equal(clicks[0].href, 'blob:local-brief'); assert.deepEqual(revoked, ['blob:local-brief']);
  } finally { dispose(); if (oldDocument === undefined) delete globalThis.document; else globalThis.document = oldDocument; URL.createObjectURL = oldCreate; URL.revokeObjectURL = oldRevoke; }
}));

test('changing board or owner invalidates preview and detached controls cannot export the new selection', () => fixture(async ({ api, board, root }) => {
  const otherInput = { ...input(root), outcome: 'A different deliverable' }, proposed = await api.act('preview', otherInput);
  const other = await api.act('create', { ...otherInput, previewDigest: proposed.execution_digest });
  const m = mounted(api);
  try { await settle(); select(m.h, '[data-select]', board.id); select(m.h, '[data-brief-owner]', 'a'); await m.h.click('brief-preview');
    const staleOwner = m.h.get('[data-brief-owner]'), staleDownload = m.h.get('[data-action="brief-download"]');
    select(m.h, '[data-select]', other.id); staleOwner.value = 'a'; staleOwner.events.change({ target: staleOwner }); await staleDownload.events.click();
    assert.equal(m.h.get('[data-action="brief-download"]').disabled, true); assert.equal(m.downloads.length, 0); assert.equal(m.h.get('[data-brief-source]').checked, false);
    select(m.h, '[data-brief-owner]', 'a'); await m.h.click('brief-preview'); const prior = m.h.get('[data-action="brief-download"]'); select(m.h, '[data-brief-owner]', 'b'); await prior.events.click();
    assert.equal(m.h.get('[data-action="brief-download"]').disabled, true); assert.equal(m.downloads.length, 0);
    await m.h.click('brief-preview'); await m.h.click('brief-download'); assert.equal(m.calls.at(-1).id, other.id); assert.equal(m.calls.at(-1).ownerId, 'b');
  } finally { m.dispose(); }
}));
