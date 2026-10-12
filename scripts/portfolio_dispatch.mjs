import { createHash } from 'node:crypto';
import { readFile, writeFile, rename } from 'node:fs/promises';

const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const json = value => JSON.stringify(value, null, 2) + '\n';
const terminal = new Set(['succeeded', 'failed', 'cancelled']);

export function assertCapabilityReceipt(invocation, receipt) {
  const request = invocation.request;
  if (receipt?.contract_id !== 'moonclaw.capability-invocation-receipt.v1' ||
      receipt.request_id !== request.request_id || receipt.attempt_id !== request.attempt_id ||
      receipt.idempotency_key !== request.idempotency_key || receipt.product_id !== request.product_id ||
      receipt.adapter_id !== invocation.adapter_id || receipt.operation_ref !== request.operation ||
      receipt.input_digest !== request.input_digest ||
      !['submitted', 'running', 'succeeded', 'failed', 'cancelled', 'unknown'].includes(receipt.status) ||
      typeof receipt.result_id !== 'string' || !receipt.result_id ||
      (receipt.status === 'succeeded' && !/^sha256:[0-9a-f]{64}$/.test(receipt.output_digest)) ||
      (receipt.status === 'failed' && !receipt.error_kind)) {
    throw Error('MoonClaw receipt does not match the exact MoonFlow attempt');
  }
  return receipt;
}

async function atomicJson(file, value) {
  const temporary = `${file}.${process.pid}.tmp`;
  await writeFile(temporary, json(value), { mode: 0o600 });
  await rename(temporary, file);
}

export async function dispatchCapability({ invocation, journalPath, receiptPath, gateway, reconcileFlow }) {
  const invocationDigest = digest(json(invocation));
  let journal;
  try { journal = JSON.parse(await readFile(journalPath, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    journal = { contract_id: 'moonproj.capability-dispatch-journal.v1', invocation_digest: invocationDigest,
      request_id: invocation.request.request_id, attempt_id: invocation.request.attempt_id,
      idempotency_key: invocation.request.idempotency_key, phase: 'prepared' };
    try { await writeFile(journalPath, json(journal), { flag: 'wx', mode: 0o600 }); }
    catch (writeError) { if (writeError.code !== 'EEXIST') throw writeError; journal = JSON.parse(await readFile(journalPath, 'utf8')); }
  }
  if (journal.contract_id !== 'moonproj.capability-dispatch-journal.v1' || journal.invocation_digest !== invocationDigest ||
      journal.request_id !== invocation.request.request_id || journal.attempt_id !== invocation.request.attempt_id ||
      journal.idempotency_key !== invocation.request.idempotency_key) throw Error('Dispatch journal belongs to another invocation');
  let receipt;
  try { receipt = assertCapabilityReceipt(invocation, JSON.parse(await readFile(receiptPath, 'utf8'))); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (!receipt || !terminal.has(receipt.status)) {
    try {
      receipt = await gateway('status', invocation);
      if (receipt) receipt = assertCapabilityReceipt(invocation, receipt);
      if (!receipt) {
        if (journal.phase === 'prepared') {
          journal.phase = 'submitting';
          await atomicJson(journalPath, journal);
          receipt = assertCapabilityReceipt(invocation, await gateway('submit', invocation));
        } else {
          // The previous submit may have reached MoonClaw. Never submit again here.
          receipt = await gateway('reconcile', invocation);
          if (receipt) receipt = assertCapabilityReceipt(invocation, receipt);
        }
      } else if (receipt.status === 'unknown' || receipt.status === 'submitted' || receipt.status === 'running') {
        const reconciled = await gateway('reconcile', invocation);
        if (reconciled) receipt = assertCapabilityReceipt(invocation, reconciled);
      }
    } catch (error) {
      journal.phase = 'unknown';
      await atomicJson(journalPath, journal);
      return { status: 'unknown', blocker: error.message, requestId: journal.request_id, attemptId: journal.attempt_id };
    }
    if (!receipt) {
      journal.phase = 'unknown';
      await atomicJson(journalPath, journal);
      return { status: 'unknown', blocker: 'MoonClaw has no reconciled receipt; inspect the native attempt before retry', requestId: journal.request_id, attemptId: journal.attempt_id };
    }
    try { await writeFile(receiptPath, json(receipt), { flag: 'wx', mode: 0o600 }); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const prior = assertCapabilityReceipt(invocation, JSON.parse(await readFile(receiptPath, 'utf8')));
      if (terminal.has(prior.status) && json(prior) !== json(receipt)) throw Error('Existing terminal MoonClaw receipt conflicts with this attempt');
      if (json(prior) !== json(receipt)) await atomicJson(receiptPath, receipt);
    }
  }
  journal.phase = terminal.has(receipt.status) ? 'receipt-recorded' : 'unknown';
  journal.receipt_digest = digest(json(receipt));
  await atomicJson(journalPath, journal);
  // The native MoonFlow reconciler is idempotent and validates the prepared identity.
  const projection = await reconcileFlow(receiptPath);
  journal.phase = terminal.has(receipt.status) ? 'flow-reconciled' : 'unknown';
  await atomicJson(journalPath, journal);
  return { status: receipt.status, requestId: receipt.request_id, attemptId: receipt.attempt_id,
    resultId: receipt.result_id, receiptDigest: journal.receipt_digest, projection };
}

export function capabilityGateway(baseUrl, { timeoutMs = 30000 } = {}) {
  if (!/^http:\/\/(?:127\.0\.0\.1|localhost):[1-9][0-9]{0,4}$/.test(baseUrl) || Number(new URL(baseUrl).port) > 65535) throw Error('MoonClaw gateway must be an exact loopback HTTP origin');
  return async (action, invocation) => {
    if (invocation.config?.provider_calls_forbidden !== false) throw Error('Provider calls remain forbidden for this MoonClaw invocation');
    if (!['status', 'submit', 'reconcile'].includes(action)) throw Error('Unsupported MoonClaw capability action');
    const response = await fetch(`${baseUrl}/v1/capability/${action}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(invocation),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (response.status === 404 && action !== 'submit') return null;
    if (!response.ok) throw Error(`MoonClaw ${action} returned HTTP ${response.status}`);
    return response.json();
  };
}
