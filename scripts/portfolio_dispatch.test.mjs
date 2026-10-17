import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { dispatchCapability, assertCapabilityReceipt, capabilityGateway } from './portfolio_dispatch.mjs';

const invocation = {
  contract_id: 'moonclaw.capability-invocation.v1', adapter_id: 'moonclaw-agent-goal-v1',
  request: { request_id: 'request-1', attempt_id: 'attempt-1', idempotency_key: 'stable-key-1',
    product_id: 'moonclaw', operation: 'moonclaw/agent.goal.execute@0.1.5',
    input_digest: `sha256:${'1'.repeat(64)}` },
};
const receipt = (status, extra = {}) => ({
  contract_id: 'moonclaw.capability-invocation-receipt.v1', result_id: `result-${status}`,
  request_id: invocation.request.request_id, attempt_id: invocation.request.attempt_id,
  idempotency_key: invocation.request.idempotency_key, product_id: invocation.request.product_id,
  adapter_id: invocation.adapter_id, operation_ref: invocation.request.operation,
  input_digest: invocation.request.input_digest, status,
  output_digest: status === 'succeeded' ? `sha256:${'2'.repeat(64)}` : '',
  output_artifacts: status === 'succeeded' ? ['outputs/result.json'] : [],
  error_kind: status === 'failed' ? 'adapter-failed' : '', ...extra,
});

async function fixture(action) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'moonproj-dispatch-'));
  try {
    return await action({ journalPath: path.join(root, 'journal.json'), receiptPath: path.join(root, 'receipt.json') });
  } finally { await rm(root, { recursive: true, force: true }); }
}

test('successful native receipt reconciles once and repeat uses durable result', () => fixture(async files => {
  const calls = [], flows = [];
  const gateway = async action => { calls.push(action); return action === 'status' ? null : receipt('succeeded'); };
  const reconcileFlow = async file => { flows.push(JSON.parse(await readFile(file, 'utf8'))); return { protocol: 'moonflow.run-projection.v3' }; };
  const first = await dispatchCapability({ invocation, ...files, gateway, reconcileFlow });
  const second = await dispatchCapability({ invocation, ...files, gateway, reconcileFlow });
  assert.equal(first.status, 'succeeded');
  assert.equal(second.resultId, first.resultId);
  assert.deepEqual(calls, ['status', 'submit']);
  assert.equal(flows.length, 2);
  assert.equal(flows[0].idempotency_key, invocation.request.idempotency_key);
}));

test('failure and remote cancellation are reconciled as actual receipts', async () => {
  for (const status of ['failed', 'cancelled']) await fixture(async files => {
    const result = await dispatchCapability({ invocation, ...files,
      gateway: async action => action === 'status' ? null : receipt(status),
      reconcileFlow: async file => JSON.parse(await readFile(file, 'utf8')) });
    assert.equal(result.status, status);
    assert.equal(result.projection.status, status);
  });
});

test('timeout becomes unknown; restart performs status and reconcile without second submit', () => fixture(async files => {
  const calls = [];
  const gateway = async action => {
    calls.push(action);
    if (action === 'status') return null;
    if (action === 'submit') throw Error('deadline exceeded');
    return receipt('succeeded');
  };
  const first = await dispatchCapability({ invocation, ...files, gateway, reconcileFlow: async () => ({}) });
  assert.equal(first.status, 'unknown');
  const recovered = await dispatchCapability({ invocation, ...files, gateway, reconcileFlow: async () => ({}) });
  assert.equal(recovered.status, 'succeeded');
  assert.deepEqual(calls, ['status', 'submit', 'status', 'reconcile']);
}));

test('missing reconciliation after an uncertain submit remains blocked, including on retry', () => fixture(async files => {
  let submits = 0;
  const gateway = async action => {
    if (action === 'submit') { submits++; throw Error('connection lost'); }
    return null;
  };
  await dispatchCapability({ invocation, ...files, gateway, reconcileFlow: async () => { throw Error('no receipt'); } });
  const retry = await dispatchCapability({ invocation, ...files, gateway, reconcileFlow: async () => { throw Error('no receipt'); } });
  assert.equal(retry.status, 'unknown');
  assert.equal(submits, 1);
}));

test('crash after receipt write replays only native MoonFlow reconciliation', () => fixture(async files => {
  let submits = 0;
  const gateway = async action => action === 'status' ? null : (submits++, receipt('succeeded'));
  await assert.rejects(() => dispatchCapability({ invocation, ...files, gateway,
    reconcileFlow: async () => { throw Error('MoonFlow stopped'); } }), /MoonFlow stopped/);
  const replay = await dispatchCapability({ invocation, ...files, gateway, reconcileFlow: async () => ({ recovered: true }) });
  assert.equal(replay.projection.recovered, true);
  assert.equal(submits, 1);
}));

test('identity and loopback transport checks fail closed', () => {
  assert.throws(() => assertCapabilityReceipt(invocation, receipt('succeeded', { attempt_id: 'other' })), /exact MoonFlow attempt/);
  assert.throws(() => capabilityGateway('https://example.com'), /exact loopback/);
  assert.throws(() => capabilityGateway('http://127.0.0.1:18123/path'), /exact loopback/);
});

test('native client sends the bare invocation to exact MoonClaw capability routes', async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, method: options.method, body: JSON.parse(options.body) });
    return url.endsWith('/status') ? { status: 404, ok: false } : { status: 200, ok: true, json: async () => receipt('succeeded') };
  };
  try {
    const gateway = capabilityGateway('http://127.0.0.1:18123');
    const authorized = { ...invocation, config: { provider_calls_forbidden: false } };
    await assert.rejects(() => gateway('submit', invocation), /forbidden/);
    assert.equal(await gateway('status', authorized), null);
    assert.equal((await gateway('submit', authorized)).status, 'succeeded');
    assert.deepEqual(calls.map(call => call.url), [
      'http://127.0.0.1:18123/v1/capability/status',
      'http://127.0.0.1:18123/v1/capability/submit',
    ]);
    assert.deepEqual(calls.map(call => call.body), [authorized, authorized]);
  } finally { globalThis.fetch = original; }
});

test('first-submit freshness may change only evaluation metadata and never the approved payload', () => fixture(async files => {
  let submits = 0;
  const result = await dispatchCapability({ invocation, ...files,
    gateway: async action => { if (action === 'submit') submits++; return null; }, reconcileFlow: async () => ({}),
    beforeSubmit: async old => ({ ...old, request: { ...old.request, operation: 'another-operation' } }),
  });
  assert.equal(result.status, 'blocked'); assert.equal(submits, 0);
  assert.match(result.blocker, /changed the approved invocation payload/);
  assert.equal(JSON.parse(await readFile(files.journalPath, 'utf8')).phase, 'prepared');
}));

test('prepared journal recovers an interrupted timestamp-only refresh but uncertain journal never refreshes or resubmits', () => fixture(async files => {
  let refreshed;
  const first = await dispatchCapability({ invocation, ...files, gateway: async () => null, reconcileFlow: async () => ({}),
    beforeSubmit: async old => { refreshed = { ...old, evaluated_at: '2026-10-12T11:00:00Z', recorded_at: '2026-10-12T11:00:00Z' }; throw Error('fixture stopped after refreshed packet persistence'); },
  });
  assert.equal(first.status, 'blocked');
  let submits = 0, refreshes = 0;
  const unknown = await dispatchCapability({ invocation: refreshed, ...files,
    gateway: async action => { if (action === 'submit') { submits++; throw Error('fixture lost response after submit'); } return null; },
    beforeSubmit: async old => { refreshes++; return old; }, reconcileFlow: async () => ({}),
  });
  assert.equal(unknown.status, 'unknown'); assert.equal(submits, 1);
  const retry = await dispatchCapability({ invocation: refreshed, ...files,
    gateway: async action => { if (action === 'submit') submits++; return action === 'reconcile' ? receipt('succeeded') : null; },
    beforeSubmit: async old => { refreshes++; return { ...old, evaluated_at: '2026-10-12T12:00:00Z' }; }, reconcileFlow: async () => ({}),
  });
  assert.equal(retry.status, 'succeeded'); assert.equal(submits, 1); assert.equal(refreshes, 1);
}));
