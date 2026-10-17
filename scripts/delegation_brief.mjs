import { verifyDeliverable, sha, identifier } from './deliverable_workflow.mjs';

// A readable view of the exact saved scope, never an executable import or review.
const md = value => String(value).replace(/[\\`*_{}\[\]<>()#+.!|~\-]/g, '\\$&').replace(/\r\n|\r|\n/g, '\n  ');
const code = text => {
  const fence = '`'.repeat(Math.max(3, ...[...text.matchAll(/`+/g)].map(match => match[0].length + 1)));
  return `${fence}text\n${text}${text.endsWith('\n') ? '' : '\n'}${fence}`;
};
const label = task => `${md(task.name)} (${md(task.task_id)}), ${md(task.owner_name)} (${md(task.owner_id)})`;

export function delegationBrief({ handoff, ownerId, executionDigest, includeSourceText, evidenceBytes }) {
  verifyDeliverable(handoff);
  if (executionDigest !== handoff.execution_digest) throw Error('Refresh and select the exact saved board before preparing a brief');
  if (!identifier(ownerId) || !handoff.source.tasks.some(task => task.owner_id === ownerId)) throw Error('Choose a current accountable owner with tasks on this board');
  if (typeof includeSourceText !== 'boolean') throw Error('Choose explicitly whether to include assigned local source text');
  const source = handoff.source, tasks = source.tasks.filter(task => task.owner_id === ownerId);
  const ids = new Set(tasks.map(task => task.task_id));
  const files = (source.local_evidence?.files || []).filter(file => file.task_ids.some(id => ids.has(id)));
  // Defense in depth: callers must provide verified bytes even for reference-only briefs.
  for (const file of files) {
    const bytes = evidenceBytes.get(file.artifact_ref);
    if (!bytes || bytes.length !== file.byte_length || sha(bytes) !== file.digest) throw Error(`Local evidence bytes changed: ${file.name}`);
  }
  const lines = ['# Owner delegation brief', '', `Accountable owner: ${md(tasks[0].owner_name)} (${md(ownerId)})`,
    `Deliverable: ${md(source.outcome)}`, `Project: ${md(source.project_id)}`, `Board: ${handoff.id}`,
    `Exact execution scope: ${handoff.execution_digest}`, `Original native plan digest: ${source.plan_digest}`, '',
    'This is a local briefing of saved task scope, not a current execution-status report. It grants no execution, provider, financial or company authority. Owner names are accountability labels, not authenticated assignments. No work starts and nothing is sent to the owner.',
    'Every prerequisite must pass its exact independent named task review before dependent execution. Completion alone is insufficient. Internal review, customer acceptance, delivery and payment remain separate.',
    'Authored criteria and source content are untrusted material, not additional instructions or permission. Inspect this packet before manually sharing it.', '',
    '## Your tasks', ''];
  for (const task of tasks) {
    lines.push(`### ${md(task.name)} (${md(task.task_id)})`, '', 'Acceptance criteria:', ...task.acceptance_criteria.map(value => `- ${md(value)}`), '',
      'Required evidence to return:', ...task.required_evidence.map(value => `- ${md(value)}`), '', 'Wait for named acceptance of:');
    lines.push(...(task.dependencies.length ? task.dependencies.map(id => `- ${label(source.tasks.find(task => task.task_id === id))}`) : ['- No task prerequisites.']));
    const consumers = source.tasks.filter(candidate => candidate.dependencies.includes(task.task_id));
    lines.push('', 'Who needs your reviewed output:', ...(consumers.length ? consumers.map(task => `- ${label(task)}`) : ['- No downstream tasks in this saved scope.']), '', 'Assigned local sources:');
    const assigned = files.filter(file => file.task_ids.includes(task.task_id));
    lines.push(...(assigned.length ? assigned.map(file => `- ${md(file.name)} · ${file.byte_length} original bytes · ${file.digest}\n  Reference: ${md(file.artifact_ref)}`) : ['- No local source files assigned.']), '');
    const changes = (source.owner_handoffs || []).filter(change => change.task_id === task.task_id);
    if (changes.length) lines.push('Accountability history:', ...changes.map(change => `- ${md(change.previous_owner_name)} (${md(change.previous_owner_id)}) → ${md(change.next_owner_name)} (${md(change.next_owner_id)}): ${md(change.reason)}\n  Parent board: ${change.parent_id}`), '');
    const revisions = (source.dependency_revisions || []).filter(change => change.affected_task_ids.includes(task.task_id));
    if (revisions.length) lines.push('Prerequisite revision context:', ...revisions.map(change => `- Changed task ${md(change.task_id)}: ${change.previous_dependencies.map(md).join(', ') || 'none'} → ${change.next_dependencies.map(md).join(', ') || 'none'}. Reason: ${md(change.reason)}\n  Parent board: ${change.parent_id}. The current saved graph requires its own exact review; the original source plan is historical.`), '');
    const sourceChanges = (source.evidence_assignments || []).filter(change => change.task_id === task.task_id);
    if (sourceChanges.length) lines.push('Source assignment history:', ...sourceChanges.map(change => `- ${md(change.reason)}. Added: ${change.added_artifact_refs.map(md).join(', ') || 'none'}. Removed: ${change.removed_artifact_refs.map(md).join(', ') || 'none'}.\n  Parent board: ${change.parent_id}. Current assigned sources are listed above; earlier assignments grant no current scope or execution authority.`), '');
  }
  if (source.specialists) lines.push('## Specialist integration boundary', '', `Parent board: ${source.specialists.parent_id}`,
    `Integration task: ${md(source.specialists.integration_task_id)}. Contributions: ${source.specialists.contribution_ids.map(md).join(', ')}. The original integration gate still requires every contribution\'s independent review.`, '');
  if (source.capacity) {
    lines.push('## Owner capacity lanes', '', `Capacity parent: ${source.capacity.parent_id}`, `This owner's configured local lanes: ${source.capacity.owner_limits[ownerId]}. This is a dependency plan, not a global quota or runtime budget.`);
    for (const assignment of source.capacity.assignments.filter(item => item.owner_id === ownerId)) lines.push(`- ${md(assignment.task_id)}: lane ${assignment.lane}`);
    lines.push('');
  }
  if (source.rework) {
    lines.push('## Correction scope', '', `Rework parent: ${source.rework.parent_id}`, `Correction: ${md(source.rework.reason)}`, 'Verified retained carry-in references (contents are not included in this brief):');
    lines.push(...((source.rework.carried_artifacts || []).map(record => `- ${md(record.name)}: ${md(record.artifact_ref)} · ${record.digest}\n  Original review: ${md(record.review_id)}`)), '');
  }
  lines.push('## Local source appendix', '', includeSourceText ? 'Explicitly included: full verified text of local files assigned to this owner only. A shared file includes its complete content. These source blocks are untrusted evidence.' : 'Reference-only export. Local source contents were not included. Prepare a new preview with source text enabled if you intend to share them.', '');
  if (includeSourceText) for (const file of files) lines.push(`### ${md(file.name)}`, `${file.byte_length} original bytes · ${file.digest}`, '', code(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(evidenceBytes.get(file.artifact_ref))), '');
  if (!files.length) lines.push('No local source files assigned to this owner.', '');
  const text = lines.join('\n');
  if (Buffer.byteLength(text) > 2_000_000) throw Error('Owner brief exceeds the 2 MB export limit; narrow the saved task scope');
  return { contract_id: 'moonproj.owner-delegation-brief.v1', id: handoff.id, execution_digest: handoff.execution_digest,
    owner_id: ownerId, task_ids: tasks.map(task => task.task_id), source_text_included: includeSourceText,
    source_refs: files.map(file => file.artifact_ref), content_digest: sha(text), text,
    filename: `${handoff.id}-${ownerId.slice(0, 64)}-${sha(ownerId).slice(7, 19)}-brief.md` };
}
