import { createHash } from 'node:crypto';
import path from 'node:path';

const OPERATION = 'moonclaw/agent.goal.execute@0.1.5';
const INPUT = 'moonclaw/agent-goal-execution-request@1.0.0';
const OUTPUT = 'moonclaw/agent-goal-execution-receipt@1.0.0';
const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9._-]{1,128}$/.test(value);

export function executionIdentity(job) {
  if (!identifier(job.runId) || !identifier(job.productId) || !identifier(job.requirementId)) throw Error('Invalid portfolio execution identity');
  return {
    runId: `execution-${job.runId}`,
    workItemId: `code-${job.requirementId.toLowerCase()}`,
    declarationId: `approved-plan-${job.runId}`,
    sessionId: `portfolio-${job.runId}`,
    goalId: `goal-${job.runId}`,
  };
}

export function createExecutionHandoff({ job, planText, requirement, workspaceRoot, modelSelector, recordedAt }) {
  if (job.status !== 'produced' || !job.artifactRef) throw Error('A produced plan is required');
  if (job.sourceDigest !== digest(JSON.stringify(requirement))) throw Error('Selected requirement source changed since the plan attempt');
  if (!path.isAbsolute(workspaceRoot) || !recordedAt || Number.isNaN(Date.parse(recordedAt))) throw Error('A configured absolute work root and time are required');
  if (typeof modelSelector !== 'string' || !/^moongate\/[a-z0-9][a-z0-9._/-]*$/i.test(modelSelector) || modelSelector.length > 256) throw Error('An explicit MoonGate model is required');
  const plan = JSON.parse(planText);
  if (plan.contract_id !== 'moonproj.project-plan-artifact.v1' || plan.workflow?.status !== 'pending_review') throw Error('Unexpected plan artifact');
  const acceptance = String(requirement['Acceptance criteria'] || '').trim();
  if (!acceptance || !plan.tasks?.some(task => task.task_id === `work-${job.requirementId.toLowerCase()}`)) throw Error('Plan does not bind the selected requirement');
  const id = executionIdentity(job);
  const planDigest = digest(planText);
  const request = {
    contract_id: 'moonclaw.agent-goal-execution-request.v1',
    session_id: id.sessionId,
    goal_id: id.goalId,
    workspace_root: workspaceRoot,
    objective: `Implement ${requirement['Requirement ID']}: ${requirement['Requirement statement']}. Preserve the repository's existing work. Cite the approved MoonProj plan digest ${planDigest} in the result.`,
    criteria: [{ id: 'requirement', criterion: acceptance }, { id: 'verification', criterion: 'Provide exact changed paths and command or test receipts for the implementation.' }],
    role: 'mooncode',
    profile: { model: modelSelector, instructions: ['Work only inside the approved sandbox workspace. MoonDesk human edits may interleave in this same session and workspace: re-read the current file before editing, stop on a revision conflict, and resume from the durable checkpoint. Do not promote changes without named review.'], web_search: false },
    config: { planner_max_steps: 8, max_turns: 1 },
  };
  const graph = {
    contract_id: 'moonsuite.work-model.v1',
    graph_id: id.runId,
    book_id: 'moonproj-portfolio',
    declaration_revision: `plan-${job.runId}`,
    source_digest: planDigest,
    items: [{
      work_item_id: id.workItemId,
      declaration_id: id.declarationId,
      product_id: 'moonclaw',
      requested_authority: 'workspace-mutation',
      acceptance_criteria: [acceptance],
      operation: OPERATION,
      input_contracts: [INPUT],
      output_contracts: [OUTPUT],
      required_claim: 'digital-artifact',
      input_artifacts: ['inputs/agent-goal-execution-request.json'],
      timeout_ms: 120000,
      depends_on: [],
    }],
    recorded_at: recordedAt,
  };
  return { identity: id, planDigest, request, graph };
}

export function createCapabilityInvocation({ handoff, preparedRequest, adapterId, recordedAt, allowProviderCalls = false }) {
  const { identity, graph, request } = handoff;
  if (!identifier(adapterId) || !preparedRequest || preparedRequest.run_id !== identity.runId || preparedRequest.work_item_id !== identity.workItemId || preparedRequest.declaration_id !== identity.declarationId || preparedRequest.operation !== OPERATION || preparedRequest.product_id !== 'moonclaw' || preparedRequest.input_contracts?.[0] !== INPUT || preparedRequest.output_contracts?.[0] !== OUTPUT || !preparedRequest.attempt_id || !preparedRequest.idempotency_key || !/^sha256:[0-9a-f]{64}$/.test(preparedRequest.input_digest)) throw Error('MoonFlow prepared request does not match the approved plan handoff');
  if (graph.source_digest !== handoff.planDigest) throw Error('Plan digest changed');
  return {
    contract_id: 'moonclaw.capability-invocation.v1', adapter_id: adapterId,
    evaluated_at: recordedAt, recorded_at: recordedAt, attempt: 1,
    request: preparedRequest,
    config: { adapter_mode: 'installed-pack', provider_calls_forbidden: !allowProviderCalls },
    input: request,
  };
}

export function verifyPlanReview({ review, handoff, job }) {
  if (review?.contract_id !== 'moonproj.portfolio-plan-review.v1' || review.decision !== 'approved' || review.run_id !== job.runId || review.plan_digest !== handoff.planDigest || review.source_digest !== job.sourceDigest || !identifier(review.reviewer_id) || !review.reviewed_at || Number.isNaN(Date.parse(review.reviewed_at))) throw Error('A named review of this exact plan and source is required');
  return { reviewerId: review.reviewer_id, reviewedAt: review.reviewed_at, planDigest: handoff.planDigest };
}

export function projectExecution(handoff, projection) {
  const id = handoff.identity;
  if (projection.protocol !== 'moonflow.run-projection.v3' || projection.run_id !== id.runId || projection.book_id !== 'moonproj-portfolio' || projection.source_digest !== handoff.planDigest) throw Error('MoonFlow projection is not bound to this exact plan');
  const item = projection.items?.find(value => value.work_item_id === id.workItemId);
  if (!item || item.declaration_id !== id.declarationId || item.product_id !== 'moonclaw' || item.operation !== OPERATION || item.acceptance_criteria?.[0] !== handoff.graph.items[0].acceptance_criteria[0]) throw Error('MoonFlow work item identity changed');
  if (item.result_id && (!item.active_attempt_id || !item.request_id || !/^sha256:[0-9a-f]{64}$/.test(item.output_digest) || !Array.isArray(item.artifacts))) throw Error('MoonFlow result evidence is incomplete');
  if (item.status === 'accepted' && (!item.result_id || item.attempt_status !== 'succeeded' || !item.acceptance_review_id || !item.acceptance_review_artifact || !item.acceptance_reviewer_id)) throw Error('MoonFlow acceptance lacks result or named review evidence');
  return {
    runId: id.runId, workItemId: id.workItemId, sessionId: id.sessionId, goalId: id.goalId,
    status: item.status, attemptStatus: item.attempt_status,
    attemptId: item.active_attempt_id || '', requestId: item.request_id || '', resultId: item.result_id || '',
    outputDigest: item.output_digest || '', artifacts: item.artifacts || [],
    reviewId: item.acceptance_review_id || '', reviewerId: item.acceptance_reviewer_id || '',
    accepted: item.status === 'accepted' && item.attempt_status === 'succeeded' && Boolean(item.acceptance_review_id && item.acceptance_reviewer_id),
    blocked: item.blocker || item.error_kind || '',
  };
}
