import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createExecutionHandoff, createCapabilityInvocation, projectExecution, verifyPlanReview } from './portfolio_execution.mjs';

const requirement = { 'Requirement ID': 'MOONPROJ-N01', 'Requirement statement': 'Deliver a working feature', 'Acceptance criteria': 'A focused native test passes' };
const job = { runId: '0123456789abcdef0123', productId: 'moonproj', requirementId: 'MOONPROJ-N01', sourceDigest: `sha256:${createHash('sha256').update(JSON.stringify(requirement)).digest('hex')}`, status: 'produced', artifactRef: '.moonsuite/products/moonproj/adapter-attempts/one/plan.json' };
const planText = JSON.stringify({ contract_id: 'moonproj.project-plan-artifact.v1', workflow: { status: 'pending_review' }, tasks: [{ task_id: 'work-moonproj-n01' }] });
const make = () => createExecutionHandoff({ job, planText, requirement, workspaceRoot: '/tmp/disposable-moonproj', modelSelector: 'moongate/kimi-k3', recordedAt: '2026-10-01T00:00:00Z' });

test('exact MoonClaw operation is bound into a MoonFlow work graph without default provider execution', () => {
  const handoff = make();
  assert.equal(handoff.graph.source_digest, handoff.planDigest);
  assert.equal(handoff.graph.items[0].operation, 'moonclaw/agent.goal.execute@0.1.5');
  assert.equal(handoff.request.profile.model, 'moongate/kimi-k3');
  assert.deepEqual(handoff.graph.items[0].acceptance_criteria, ['A focused native test passes']);
  assert.throws(() => createExecutionHandoff({ job, planText, requirement: { ...requirement, 'Acceptance criteria': 'changed' }, workspaceRoot: '/tmp/copy', modelSelector: 'moongate/kimi-k3', recordedAt: '2026-10-01T00:00:00Z' }), /source changed/);
  assert.throws(() => createExecutionHandoff({ job, planText, requirement, workspaceRoot: '/tmp/copy', modelSelector: 'codex/gpt-5.6-sol', recordedAt: '2026-10-01T00:00:00Z' }), /MoonGate model/);
});

test('named plan review binds the exact artifact and source before handoff', () => {
  const handoff = make();
  const review = { contract_id: 'moonproj.portfolio-plan-review.v1', decision: 'approved', run_id: job.runId, plan_digest: handoff.planDigest, source_digest: job.sourceDigest, reviewer_id: 'founder', reviewed_at: '2026-10-01T00:01:00Z' };
  assert.equal(verifyPlanReview({ review, handoff, job }).reviewerId, 'founder');
  assert.throws(() => verifyPlanReview({ review: { ...review, plan_digest: `sha256:${'0'.repeat(64)}` }, handoff, job }), /exact plan/);
});

test('prepared attempt identity is required and provider calls remain forbidden by default', () => {
  const handoff = make();
  const preparedRequest = { run_id: handoff.identity.runId, work_item_id: handoff.identity.workItemId, declaration_id: handoff.identity.declarationId, operation: handoff.graph.items[0].operation, product_id: 'moonclaw', input_contracts: handoff.graph.items[0].input_contracts, output_contracts: handoff.graph.items[0].output_contracts, attempt_id: 'attempt-1', idempotency_key: 'key-1', input_digest: `sha256:${'0'.repeat(64)}` };
  const invocation = createCapabilityInvocation({ handoff, preparedRequest, adapterId: 'moonclaw-agent-goal-v1', recordedAt: '2026-10-01T00:02:00Z' });
  assert.equal(invocation.config.provider_calls_forbidden, true);
  assert.equal(invocation.request.idempotency_key, 'key-1');
  assert.throws(() => createCapabilityInvocation({ handoff, preparedRequest: { ...preparedRequest, run_id: 'other' }, adapterId: 'moonclaw-agent-goal-v1', recordedAt: '2026-10-01T00:02:00Z' }), /does not match/);
});

test('actual MoonFlow result and independent review correlate only to original plan', () => {
  const handoff = make();
  const item = { ...handoff.graph.items[0], status: 'accepted', attempt_status: 'succeeded', active_attempt_id: 'attempt-1', request_id: 'request-1', result_id: 'result-1', output_digest: `sha256:${'2'.repeat(64)}`, artifacts: ['results/receipt.json'], acceptance_review_id: 'review-1', acceptance_review_artifact: 'reviews/result.json', acceptance_reviewer_id: 'founder' };
  const projection = { protocol: 'moonflow.run-projection.v3', run_id: handoff.identity.runId, book_id: 'moonproj-portfolio', source_digest: handoff.planDigest, items: [item] };
  assert.equal(projectExecution(handoff, projection).accepted, true);
  assert.equal(projectExecution(handoff, { ...projection, items: [{ ...item, status: 'review' }] }).accepted, false);
  assert.throws(() => projectExecution(handoff, { ...projection, source_digest: `sha256:${'3'.repeat(64)}` }), /exact plan/);
});
