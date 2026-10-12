import test from 'node:test';
import assert from 'node:assert/strict';
import { HEADERS, parseCsv, emptyWorkspace, previewImport, commitImport, savePlan, totals, rowFingerprint, mountWorkspace, validateWorkspace, createBackup, parseBackup, previewRestore, commitRestore, persistWorkspace } from '../opc_public/prd_workspace.js';

const digest = digit => digit.repeat(64);
const time = '2026-10-01T00:00:00.000Z';

const row = (id = 'MOONPROJ-B01', extra = {}) => ({
  Product: 'MoonProj', 'Requirement ID': id, Scope: 'baseline', Priority: 'P0',
  'Requirement title': 'A "quoted" title', 'Evidence assessment': 'Verified local',
  'Current assessment': 'Verified local', 'Requirement statement': 'A founder can plan; no self-verification.',
  'Acceptance criteria': 'Check once,\nthen again.', 'Evidence and sources': 'source.md#anchor', Dependencies: '', ...extra,
});
const csv = rows => [HEADERS.join(','), ...rows.map(r => HEADERS.map(h => `"${String(r[h]).replaceAll('"', '""')}"`).join(','))].join('\r\n');

test('RFC4180 quoted commas, quotes, newlines and evidence assessment round trip', () => {
  const parsed = parseCsv(csv([row()]));
  assert.deepEqual(parsed, [row()]);
  assert.equal(parsed[0]['Evidence assessment'], 'Verified local');
});
test('malformed files, duplicate IDs and unsupported scope are rejected', () => {
  assert.throws(() => parseCsv('nonsense\nvalue'), /columns/);
  assert.throws(() => parseCsv(csv([row(), row()])), /Duplicate/);
  assert.throws(() => parseCsv(csv([row('MOONPROJ-B02', { Scope: 'retirement' })])), /invalid scope/);
  assert.throws(() => parseCsv(csv([row()]).slice(0, -1)), /Unclosed CSV quote/);
});
test('MoonProj first, collection addition, repeated import and label conflict', () => {
  const first = parseCsv(csv([row()]));
  const p1 = previewImport(emptyWorkspace(), first, digest('1'), 'moonproj-v1');
  let store = commitImport(emptyWorkspace(), p1, time);
  assert.equal(previewImport(store, first, digest('1'), 'moonproj-v1').duplicate, true);
  assert.equal(previewImport(store, first, digest('2'), 'moonproj-v1').duplicate, true);
  const collection = parseCsv(csv([row(), row('MOONPROJ-N01', { Scope: 'quality' })]));
  const p2 = previewImport(store, collection, digest('2'), 'portfolio-v1');
  assert.deepEqual([p2.added, p2.changed], [1, 0]);
  store = commitImport(store, p2, '2026-10-01T01:00:00.000Z');
  assert.deepEqual(totals(store.versions.at(-1).rows), { rows: 2, products: 1, baseline: 1, roadmap: 0, quality: 1, retirement: 0 });
  assert.equal(store.versions.length, 2);
  const changedCollection = [collection[0], { ...collection[1], 'Requirement title': 'Revised quality check' }];
  assert.throws(() => previewImport(store, changedCollection, digest('3'), 'portfolio-v1'), /label/);
  assert.throws(() => previewImport(store, [collection[1]], digest('4'), 'portfolio-v2'), /would disappear/);
});
test('plans are separate from source evidence, survive version updates and become stale when source changes', () => {
  let store = commitImport(emptyWorkspace(), previewImport(emptyWorkspace(), [row()], digest('1'), 'v1'), time);
  store = savePlan(store, 'MOONPROJ-B01', { owner: 'Founder', priority: 'P1', plannedWork: 'Improve import', taskRef: 'OPC-TASK-123', proposedEvidence: 'Proposed browser regression' });
  assert.equal(store.versions[0].rows[0]['Evidence assessment'], 'Verified local');
  assert.equal(store.plans['MOONPROJ-B01'].proposedEvidence, 'Proposed browser regression');
  assert.throws(() => savePlan(store, 'MOONPROJ-B01', { taskRef: 'https://host/?token=secret' }), /task reference/);
  const changed = row('MOONPROJ-B01', { 'Acceptance criteria': 'New acceptance' });
  store = commitImport(store, previewImport(store, [changed], digest('2'), 'v2'), '2026-10-01T01:00:00.000Z');
  assert.equal(store.plans['MOONPROJ-B01'].owner, 'Founder');
  assert.notEqual(store.plans['MOONPROJ-B01'].sourceFingerprint, rowFingerprint(changed));
});


test('Projects page renders imported source and truthful release boundary after reload', () => {
  let store = emptyWorkspace();
  store = commitImport(store, previewImport(store, [row()], digest('1'), 'moonproj-v1'), time);
  store = savePlan(store, 'MOONPROJ-B01', { owner: 'Founder', plannedWork: 'Synthetic plan', proposedEvidence: 'Proposed only' });
  const storage = { getItem: () => JSON.stringify(store), setItem: () => { throw new Error('render should not write'); } };
  const host = { isConnected: true, innerHTML: '', querySelector: () => null, querySelectorAll: () => [] };
  mountWorkspace(host, storage);
  assert.match(host.innerHTML, /MOONPROJ-B01/);
  assert.match(host.innerHTML, /来源评估（未重新验证）/);
  assert.match(host.innerHTML, /发布就绪：未独立验证/);
  assert.match(host.innerHTML, /Synthetic plan/);
});

test('unreadable local state still allows PRD product navigation for recovery', () => {
  let openProduct;
  const host = {
    isConnected: true, innerHTML: '', querySelector: () => null, querySelectorAll: () => [],
    addEventListener(name, handler) { if (name === 'moonproj:open-prd') openProduct = handler; },
  };
  mountWorkspace(host, { getItem: () => '{corrupt', setItem: () => { throw new Error('should not write'); } });
  assert.match(host.innerHTML, /Cannot open stored workspace/);
  assert.doesNotThrow(() => openProduct({ detail: { product: 'MoonProj' } }));
  assert.match(host.innerHTML, /先导出原始损坏记录/);
});

test('JSON backup roundtrips full version history, plans and source provenance', async () => {
  let store = emptyWorkspace();
  store = commitImport(store, previewImport(store, [row()], digest('1'), 'moonproj-v1', 'MoonProj.csv'), time);
  store = savePlan(store, 'MOONPROJ-B01', { owner: 'Founder', plannedWork: 'Synthetic review', proposedEvidence: 'Proposed only' });
  const file = await createBackup(store, time);
  const restored = await parseBackup(file);
  assert.equal(restored.integrity, 'checksum-matched');
  assert.deepEqual(restored.workspace, store);
  const preview = previewRestore(emptyWorkspace(), restored.workspace);
  assert.equal(preview.addedVersions, 1);
  assert.equal(preview.addedPlans, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(commitRestore(preview))), store);
  assert.equal(previewRestore(store, restored.workspace).noop, true);
  const tampered = JSON.parse(file); tampered.workspace.versions[0].rows[0]['Evidence assessment'] = 'Blocked';
  await assert.rejects(parseBackup(JSON.stringify(tampered)), /checksum mismatch/);
  assert.equal((await parseBackup(JSON.stringify(store))).integrity, 'legacy-unchecked');
});

test('restore rejects malformed, injected, removed-ID and divergent histories without changing local data', async () => {
  let original = emptyWorkspace();
  original = commitImport(original, previewImport(original, [row()], digest('1'), 'v1'), time);
  original = savePlan(original, 'MOONPROJ-B01', { owner: 'Current founder', plannedWork: 'Current plan' });
  const before = JSON.stringify(original);
  const poisoned = structuredClone(original);
  poisoned.plans['MOONPROJ-B01'].verified = true;
  assert.throws(() => validateWorkspace(poisoned), /Invalid plan/);
  const removed = structuredClone(original);
  removed.versions.push({ ...removed.versions[0], digest: digest('2'), label: 'v2', importedAt: '2026-10-01T01:00:00.000Z', rows: [row('MOONPROJ-B02')] });
  removed.activeDigest = digest('2');
  assert.throws(() => validateWorkspace(removed), /removed/);
  const incoming = commitImport(emptyWorkspace(), previewImport(emptyWorkspace(), [row('MOONPROJ-B02')], digest('2'), 'other'), time);
  assert.throws(() => previewRestore(original, incoming), /diverges/);
  await assert.rejects(parseBackup('{broken json'), /cannot be parsed/);
  assert.equal(JSON.stringify(original), before);
});

test('compatible restore keeps local conflicting plans only with explicit confirmation', () => {
  let local = commitImport(emptyWorkspace(), previewImport(emptyWorkspace(), [row()], digest('1'), 'v1'), time);
  local = savePlan(local, 'MOONPROJ-B01', { owner: 'Local', plannedWork: 'Current plan' });
  let incoming = commitImport(local, previewImport(local, [row(), row('MOONPROJ-N01', { Scope: 'quality' })], digest('2'), 'v2'), '2026-10-01T01:00:00.000Z');
  incoming = savePlan(incoming, 'MOONPROJ-B01', { owner: 'Backup', plannedWork: 'Other plan' });
  incoming = savePlan(incoming, 'MOONPROJ-N01', { owner: 'Backup', plannedWork: 'New plan' });
  const preview = previewRestore(local, incoming);
  assert.deepEqual([preview.addedVersions, preview.addedPlans, preview.conflicts], [1, 1, ['MOONPROJ-B01']]);
  assert.throws(() => commitRestore(preview), /Choose explicitly/);
  const merged = commitRestore(preview, true);
  assert.equal(merged.plans['MOONPROJ-B01'].owner, 'Local');
  assert.equal(merged.plans['MOONPROJ-N01'].owner, 'Backup');
  assert.equal(merged.versions.length, 2);
  assert.equal(previewRestore(merged, incoming).addedVersions, 0);
});

test('storage failure and escaped imported markup do not overwrite or execute data', () => {
  let store = commitImport(emptyWorkspace(), previewImport(emptyWorkspace(), [row()], digest('1'), 'v1'), time);
  const old = JSON.stringify(store);
  const storage = { data: old, setItem() { throw new Error('quota'); }, getItem() { return this.data; } };
  assert.throws(() => persistWorkspace(storage, savePlan(store, 'MOONPROJ-B01', { owner: 'New' })), /quota/);
  assert.equal(storage.data, old);
  const injected = row('MOONPROJ-B01', { 'Requirement title': '<img src=x onerror=alert(1)>' });
  store = commitImport(emptyWorkspace(), previewImport(emptyWorkspace(), [injected], digest('3'), 'v1'), time);
  const host = { isConnected: true, innerHTML: '', querySelector: () => null, querySelectorAll: () => [] };
  mountWorkspace(host, { getItem: () => JSON.stringify(store), setItem: () => {} });
  assert.match(host.innerHTML, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.doesNotMatch(host.innerHTML, /<img src=x/);
});
