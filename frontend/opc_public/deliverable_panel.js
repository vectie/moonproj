import { acceptanceRows, acceptanceMap, readNativePlanFile } from './deliverable_acceptance.js';
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// Keep original bytes, including UTF-8 BOM and CRLF; previews never reserialize JSON/CSV.
export async function readEvidenceFiles(files) {
  if (files.length > 12) throw Error('Choose at most 12 local evidence files');
  let total = 0;
  const names = new Set(), result = [];
  for (const file of files) {
    if (!/\.(txt|md|markdown|json|csv)$/i.test(file.name) || file.name.length > 120 || /[\\/\x00-\x1f\x7f]/.test(file.name) || names.has(file.name)) throw Error('Choose unique TXT, MD, Markdown, JSON or CSV filenames without paths');
    names.add(file.name);
    if (!file.size || file.size > 131072 || (total += file.size) > 262144) throw Error('Use nonempty files, at most 128 KiB each and 256 KiB total');
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.length !== file.size) throw Error('Selected file changed while reading; choose it again');
    let text;
    try { text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); } catch { throw Error('Evidence must contain valid UTF-8 text'); }
    if (/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(text)) throw Error('Evidence contains unsupported binary control characters');
    let binary = ''; for (const byte of bytes) binary += String.fromCharCode(byte);
    const digest = `sha256:${Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('')}`;
    result.push({ name: file.name, content_base64: btoa(binary), task_ids: [], text, digest, byte_length: bytes.length, inspected: false });
  }
  return result;
}
function evidenceMapping(source, inspect = false) {
  const files = source?.local_evidence?.files || [];
  return `<ul>${(source?.tasks || []).map(task => `<li><strong>${esc(task.name)}</strong> (${esc(task.task_id)}) · ${esc(task.owner_name)} (${esc(task.owner_id)})<br>Prerequisites: ${esc(task.dependencies.join(', ') || 'none')}<br>Acceptance: ${esc(task.acceptance_criteria.join('; '))}<br>Required outputs: ${esc(task.required_evidence.join('; '))}<ul>${files.filter(file => file.task_ids.includes(task.task_id)).map(file => `<li>${esc(file.name)} · ${file.byte_length} bytes · ${esc(file.digest)}<br>${esc(file.artifact_ref)}${inspect ? `<button type="button" data-action="inspect-evidence" data-artifact="${esc(file.artifact_ref)}">Inspect saved ${esc(file.name)}</button>` : ''}</li>`).join('') || '<li>No local evidence assigned</li>'}</ul></li>`).join('')}</ul>`;
}

export function specialistRows(item, count = 2, existing = []) {
  const owners = [...new Set((item?.tasks || []).map(t => t.owner_id))];
  const ids = new Set([...(item?.tasks || []).map(t => t.task_id), ...existing.map(t => t.task_id)]);
  return Array.from({ length: count }, (_, index) => {
    let n = 1; while (ids.has(`specialist-${n}`)) n++;
    const task_id = `specialist-${n}`; ids.add(task_id);
    return { task_id, name: '', owner_id: owners[(existing.length + index) % owners.length] || '', criteria: '', evidence: '' };
  });
}

function sourceAssignmentEditor(item, draft, busy) {
  const files = item.source?.local_evidence?.files;
  if (item.status !== 'awaiting_import' || !files?.length || item.source.rework) return '';
  const task = item.tasks.find(task => task.task_id === draft.sourceTask);
  const revision = draft.sourcePreview?.source.evidence_assignments.at(-1);
  const names = refs => refs.map(ref => files.find(file => file.artifact_ref === ref)?.name || ref).join(', ') || 'none';
  return `<details ${draft.sourceTask || draft.sourceBusy ? 'open' : ''}><summary>Assign source evidence to a task</summary>
    <p>Choose which saved source files this task should use, including new specialist contributions. Source files are not inherited automatically. This saves a separate review-pending board; task owners, prerequisites and acceptance remain unchanged.</p>
    <label>Task receiving source evidence <select data-source-task ${busy ? 'disabled' : ''}><option value="">Choose a task</option>${item.tasks.map(candidate => `<option value="${esc(candidate.task_id)}" ${candidate.task_id === draft.sourceTask ? 'selected' : ''}>${esc(candidate.name)} (${esc(candidate.task_id)}) · ${esc(candidate.owner_name)}</option>`).join('')}</select></label>
    ${task ? `<fieldset><legend>Saved files assigned to ${esc(task.name)} (${esc(task.task_id)})</legend>${files.map(file => `<label><input type="checkbox" data-source-ref="${esc(file.artifact_ref)}" ${(draft.sourceRefs || []).includes(file.artifact_ref) ? 'checked' : ''} ${busy ? 'disabled' : ''}>${esc(file.name)} · ${file.byte_length} bytes · ${esc(file.digest)}<br>Currently assigned to: ${esc(file.task_ids.join(', '))}</label>`).join('')}</fieldset><p>Inspect saved source content in the mapping above. Each file must retain at least one task; assign its new task before removing its last assignment. These are task scope declarations, not file-access isolation.</p>` : ''}
    <label>Reason for this source assignment <textarea data-field="sourceReason" maxlength="4096" ${busy ? 'disabled' : ''}>${esc(draft.sourceReason || '')}</textarea></label>
    <button type="button" data-action="source-assignment-preview" ${busy || !task ? 'disabled' : ''}>Preview source assignment</button>
    <div data-source-preview>${revision ? `<p>Task: ${esc(revision.task_id)}<br>Added sources: ${esc(names(revision.added_artifact_refs))}<br>Removed sources: ${esc(names(revision.removed_artifact_refs))}<br>Reason: ${esc(revision.reason)}<br>Exact new review digest: ${esc(draft.sourcePreview.execution_digest)}</p><p>The parent review cannot authorize this scope. Inspect every task's source mapping and the generated input references:</p>${evidenceMapping(draft.sourcePreview.source)}<details><summary>Complete proposed graph and input references</summary><pre>${esc(JSON.stringify(draft.sourcePreview.graph, null, 2))}</pre></details>` : '<p>Preview this exact source selection before saving.</p>'}</div>
    <button type="button" data-action="source-assignment" ${busy || !revision ? 'disabled' : ''}>Save review-pending source assignment</button>
    <button type="button" data-action="source-assignment-cancel" ${busy && !draft.sourceBusy ? 'disabled' : ''}>Cancel source assignment draft</button>
  </details>`;
}

function prerequisiteEditor(item, draft, busy) {
  if (item.status !== 'awaiting_import' || !item.source || item.source.capacity || item.source.specialists || item.source.rework) return '';
  const task = item.tasks.find(task => task.task_id === draft.dependencyTask);
  const revision = draft.dependencyPreview?.source.dependency_revisions.at(-1);
  return `<details ${draft.dependencyTask || draft.dependencyBusy ? 'open' : ''}><summary>Revise task prerequisites</summary>
    <p>Choose what this task must wait for before import. Save a separate review-pending board with unchanged owners, acceptance and source bytes. Revise before capacity or specialist planning.</p>
    <label>Task to revise <select data-dependency-task ${busy ? 'disabled' : ''}><option value="">Choose a task</option>${item.tasks.map(candidate => `<option value="${esc(candidate.task_id)}" ${candidate.task_id === draft.dependencyTask ? 'selected' : ''}>${esc(candidate.name)} (${esc(candidate.task_id)}) · ${esc(candidate.owner_name)}</option>`).join('')}</select></label>
    ${task ? `<p>Current prerequisites: ${esc(task.dependencies.join(', ') || 'none')}</p><fieldset><legend>Wait for named acceptance of these tasks</legend>${item.tasks.filter(candidate => candidate.task_id !== task.task_id).map(candidate => `<label><input type="checkbox" data-dependency-prerequisite="${esc(candidate.task_id)}" ${(draft.dependencyIds || []).includes(candidate.task_id) ? 'checked' : ''} ${busy ? 'disabled' : ''}>${esc(candidate.name)} (${esc(candidate.task_id)}) · ${esc(candidate.owner_name)} (${esc(candidate.owner_id)})</label>`).join('') || '<p>No other tasks available.</p>'}</fieldset><p>Uncheck every prerequisite to propose an independent task. Cycles are rejected.</p>` : ''}
    <label>Reason for this prerequisite change <textarea data-field="dependencyReason" maxlength="4096" ${busy ? 'disabled' : ''}>${esc(draft.dependencyReason || '')}</textarea></label>
    <button type="button" data-action="prerequisites-preview" ${busy || !task ? 'disabled' : ''}>Preview prerequisite revision</button>
    <div data-dependency-preview>${revision ? `<p>Added: ${esc(revision.added_dependencies.join(', ') || 'none')}<br>Removed: ${esc(revision.removed_dependencies.join(', ') || 'none')}<br>Changed task and downstream tasks: ${esc(revision.affected_task_ids.join(', '))}<br>Reason: ${esc(revision.reason)}<br>Exact new review digest: ${esc(draft.dependencyPreview.execution_digest)}</p><p>The parent's review cannot authorize this board. Inspect the complete proposed task scope:</p>${evidenceMapping(draft.dependencyPreview.source)}<details><summary>Complete revised graph</summary><pre>${esc(JSON.stringify(draft.dependencyPreview.graph, null, 2))}</pre></details>` : '<p>Preview this exact prerequisite selection before saving.</p>'}</div>
    <button type="button" data-action="prerequisites" ${busy || !revision ? 'disabled' : ''}>Save review-pending prerequisite revision</button>
    <button type="button" data-action="prerequisites-cancel" ${busy && !draft.dependencyBusy ? 'disabled' : ''}>Cancel prerequisite draft</button>
  </details>`;
}

export function renderDeliverablePanel({ entries, selected, draft, busy, error, notice, assembly }) {
  const item = entries.find(e => e.id === selected);
  const planTasks = draft.acceptanceRows || [];
  const evidence = draft.evidenceFiles || [];
  const contributions = draft.specialistRows || specialistRows(item);
  const owners = [...new Map((item?.tasks || []).map(t => [t.owner_id, t.owner_name])).entries()];
  return `<section class="portfolio-actions" aria-label="Delegate a deliverable"><h3>Delegate a deliverable</h3>
    <p>Use a saved native project plan with named owners and prerequisites. Review the exact scope before importing it into MoonFlow. Agent outputs return for independent task review.</p>
    ${error ? `<p role="alert" class="prd-error">${esc(error)}</p>` : ''}${notice ? `<p role="status">${esc(notice)}</p>` : ''}
    <details ${entries.length ? '' : 'open'}><summary>Start from a saved plan</summary>
      <label>Desired deliverable <input data-field="outcome" value="${esc(draft.outcome)}" maxlength="4096" ${busy ? 'disabled' : ''}></label>
      <label>Native project-plan artifact JSON <textarea data-field="planText" rows="7" ${busy ? 'disabled' : ''}>${esc(draft.planText)}</textarea></label>
      <label>Load saved native plan <input type="file" data-plan-file accept=".json,application/json" ${busy ? 'disabled' : ''}></label>
      <p>Choose the native plan JSON saved from Projects, or paste it above. Loading a different plan clears task acceptance edits and source assignments. It does not change any saved board.</p>
      ${draft.planError ? `<p role="alert">${esc(draft.planError)}</p>` : ''}
      <fieldset><legend>Task-by-task acceptance</legend><p>Inspect each task and its original gates. Milestone/project gates are context: enter explicit criteria and required evidence for that task. Existing task-scoped gates are prefilled for review.</p>
      ${planTasks.map(task => `<fieldset><legend>${esc(task.name)} (${esc(task.task_id)})</legend><p>Accountable owner: ${esc(task.owner_name)} (${esc(task.owner_id)}). Prerequisites: ${esc(task.dependencies.join(', ') || 'none')}.</p><details open><summary>Original plan acceptance gates</summary><ul>${task.gates.map(gate => `<li>${esc(gate.gate_id)} · ${esc(gate.scope_type)} ${esc(gate.scope_id)}${gate.scope_type !== 'task' ? ' · inherited context, adapt below' : ''}<br>Criteria: ${esc(gate.criteria.join('; '))}<br>Required evidence: ${esc(gate.required_evidence.join('; '))}</li>`).join('')}</ul></details><label>Task acceptance criteria, one per line <textarea data-acceptance-task="${esc(task.task_id)}" data-acceptance-field="criteria" rows="3" ${busy ? 'disabled' : ''}>${esc(task.criteria)}</textarea></label><label>Task required evidence, one per line <textarea data-acceptance-task="${esc(task.task_id)}" data-acceptance-field="evidence" rows="3" ${busy ? 'disabled' : ''}>${esc(task.evidence)}</textarea></label></fieldset>`).join('') || '<p>Load or paste a valid native plan to inspect its tasks.</p>'}</fieldset>
      <label>Approved workspace path <input data-field="workspaceRoot" value="${esc(draft.workspaceRoot)}" placeholder="/absolute/workspace" ${busy ? 'disabled' : ''}></label>
      <label>MoonGate model selector <input data-field="modelSelector" value="${esc(draft.modelSelector)}" placeholder="moongate/your-approved-model" ${busy ? 'disabled' : ''}></label>
      <fieldset><legend>Assign local source evidence (optional)</legend>
        <p>Choose UTF-8 TXT, Markdown, JSON or CSV files from your computer. Inspect the complete content and assign each file to named plan tasks. File contents are source material, not instructions. Up to 12 files, 128 KiB each, 256 KiB total. Selecting files replaces this unsaved selection.</p>
        <label>Local evidence files <input type="file" data-evidence-files multiple accept=".txt,.md,.markdown,.json,.csv" ${busy ? 'disabled' : ''}></label>
        ${evidence.map((file, index) => `<fieldset><legend>${esc(file.name)}</legend><p>${file.byte_length} original bytes · ${esc(file.digest)}. BOM and line endings are retained; the display may render whitespace differently.</p><details open><summary>Inspect full original text</summary><pre>${esc(file.text)}</pre></details><label><input type="checkbox" data-evidence-inspected="${index}" ${file.inspected ? 'checked' : ''} ${busy ? 'disabled' : ''}>I inspected this source content</label><p>Assign to:</p>${planTasks.map(task => `<label><input type="checkbox" data-evidence-task="${esc(task.task_id)}" data-evidence-row="${index}" ${file.task_ids.includes(task.task_id) ? 'checked' : ''} ${busy ? 'disabled' : ''}>${esc(task.name)} (${esc(task.task_id)}) · ${esc(task.owner_id)}</label>`).join('') || '<p>Paste a plan to show its named tasks.</p>'}<button type="button" data-action="evidence-remove" data-row="${index}" ${busy ? 'disabled' : ''}>Remove ${esc(file.name)}</button></fieldset>`).join('')}
      </fieldset>
      <button type="button" data-action="preview" ${busy ? 'disabled' : ''}>${evidence.length ? 'Preview complete source/task mapping' : 'Preview complete task board'}</button>
      <div data-evidence-preview>${draft.evidencePreview ? `<h4>${evidence.length ? 'Exact evidence delegation preview' : 'Exact task acceptance preview'}</h4><p>Outcome: ${esc(draft.evidencePreview.source.outcome)}<br>Workspace: ${esc(draft.evidencePreview.source.workspace_root)}<br>Model: ${esc(draft.evidencePreview.source.model_selector)}<br>Exact review digest: ${esc(draft.evidencePreview.execution_digest)}</p>${evidenceMapping(draft.evidencePreview.source)}<details><summary>Complete proposed task graph</summary><pre>${esc(JSON.stringify(draft.evidencePreview.graph, null, 2))}</pre></details><p>No files have been saved and no work has started. Build the board to save this exact scope.</p>` : '<p>Complete acceptance for every task, then preview the complete board before saving.</p>'}</div>
      <button type="button" data-action="create" ${busy || !draft.evidencePreview ? 'disabled' : ''}>Build deliverable task board</button>
      <button type="button" data-action="cancel-draft" ${busy && !draft.cancelable ? 'disabled' : ''}>Cancel unsaved task draft</button>
      <p>This saves a local proposal. Plan owners are accountability labels, not authenticated company assignments. No work starts.</p></details>
    <label>Saved deliverable <select data-select ${busy ? 'disabled' : ''}><option value="">Choose a deliverable</option>${entries.map(e => `<option value="${esc(e.id)}" ${e.id === selected ? 'selected' : ''}>${esc(e.outcome || e.id)} · ${esc(e.status)}</option>`).join('')}</select></label>
    <button type="button" data-action="refresh" ${busy ? 'disabled' : ''}>Refresh native state</button>
    ${item ? `<h4>${esc(item.outcome || item.id)}</h4><p>Status: ${esc(item.status)}${item.blocker ? ` · ${esc(item.blocker)}` : ''}</p>
      ${item.execution_digest ? `<p>Exact review digest: ${esc(item.execution_digest)}</p><p>Import and dispatch require the operator's deliverable_review_file to approve this digest. Provider calls need separate explicit approval in that review.</p>` : ''}
      ${item.execution_digest && item.source && !item.blocker ? `<details ${draft.briefOpen || draft.briefPreview || draft.briefBusy ? 'open' : ''}><summary>Prepare an owner delegation brief</summary><p>Choose the current accountable owner and inspect their task acceptance, prerequisite owners and downstream handoffs. Download stays local and grants no execution or company authority.</p><label>Brief owner <select data-brief-owner ${busy ? 'disabled' : ''}><option value="">Choose an owner</option>${owners.map(([id, name]) => `<option value="${esc(id)}" ${id === draft.briefOwner ? 'selected' : ''}>${esc(name)} (${esc(id)})</option>`).join('')}</select></label><label><input type="checkbox" data-brief-source ${draft.briefIncludeSource ? 'checked' : ''} ${busy ? 'disabled' : ''}>Include full text of this owner's assigned local sources</label><p>Source text is excluded by default. Enabling it includes complete shared files too; inspect their contents before sharing the download.</p><button type="button" data-action="brief-preview" ${busy || !draft.briefOwner ? 'disabled' : ''}>Preview owner brief</button><div data-brief-preview>${draft.briefPreview ? `<p>${draft.briefPreview.task_ids.length} tasks · ${draft.briefPreview.source_refs.length} source references · Source text ${draft.briefPreview.source_text_included ? 'included' : 'excluded'}<br>Packet digest: ${esc(draft.briefPreview.content_digest)}</p><label>Inspect complete owner brief <textarea readonly rows="18" aria-label="Owner delegation brief text">${esc(draft.briefPreview.text)}</textarea></label>` : '<p>Preview this exact owner selection before downloading.</p>'}</div><button type="button" data-action="brief-download" ${busy || !draft.briefPreview ? 'disabled' : ''}>Download owner brief Markdown</button><button type="button" data-action="brief-cancel" ${busy && !draft.briefBusy ? 'disabled' : ''}>Close owner brief</button></details>` : ''}
      ${item.source?.local_evidence ? `<details open><summary>Saved local source/task mapping</summary>${evidenceMapping(item.source, true)}</details>` : ''}
      ${draft.inspectedEvidence ? `<h4>Saved source: ${esc(draft.inspectedEvidence.name)}</h4><p>${esc(draft.inspectedEvidence.digest)} · ${draft.inspectedEvidence.byte_length} original bytes</p><pre>${esc(draft.inspectedEvidence.text)}</pre>` : ''}
      ${sourceAssignmentEditor(item, draft, busy)}
      ${item.source?.evidence_assignments?.length ? `<details><summary>Source assignment history (${item.source.evidence_assignments.length})</summary><ul>${item.source.evidence_assignments.map(change => `<li>${esc(change.task_id)}: ${esc(change.reason)}. Added: ${esc(change.added_artifact_refs.join(', ') || 'none')}. Removed: ${esc(change.removed_artifact_refs.join(', ') || 'none')}. Parent: ${esc(change.parent_id)}. Parent digest: ${esc(change.parent_execution_digest)}.</li>`).join('')}</ul><p>The saved mapping above is current; earlier assignments are historical.</p></details>` : ''}
      ${item.source?.owner_handoffs?.length ? `<details><summary>Owner handoff history (${item.source.owner_handoffs.length})</summary><ul>${item.source.owner_handoffs.map(h => `<li>${esc(h.task_id)}: ${esc(h.previous_owner_name)} (${esc(h.previous_owner_id)}) → ${esc(h.next_owner_name)} (${esc(h.next_owner_id)}). ${esc(h.reason)}. Parent: ${esc(h.parent_id)}</li>`).join('')}</ul></details>` : ''}
      ${item.source?.dependency_revisions?.length ? `<details><summary>Prerequisite revision history (${item.source.dependency_revisions.length})</summary><ul>${item.source.dependency_revisions.map(revision => `<li>${esc(revision.task_id)}: ${esc(revision.previous_dependencies.join(', ') || 'none')} → ${esc(revision.next_dependencies.join(', ') || 'none')}. ${esc(revision.reason)}. Parent: ${esc(revision.parent_id)}. Parent digest: ${esc(revision.parent_execution_digest)}.</li>`).join('')}</ul><p>The original native plan is historical. Current prerequisites are in this board's exact proposed graph.</p></details>` : ''}
      ${prerequisiteEditor(item, draft, busy)}
      ${item.status === 'awaiting_import' && !item.source?.capacity && !item.source?.specialists && !item.source?.rework ? `<details><summary>Hand off a task to another owner</summary><p>Change accountability before capacity or specialist planning. Acceptance, evidence and prerequisites stay exact. The new board requires its own review.</p><label>Task ID <input data-field="handoffTask" value="${esc(draft.handoffTask || '')}" ${busy ? 'disabled' : ''}></label><label>New owner ID <input data-field="handoffOwner" value="${esc(draft.handoffOwner || '')}" ${busy ? 'disabled' : ''}></label><p>Use an owner from the original native plan. Current owners: ${esc([...new Set((item.tasks || []).map(t => `${t.owner_id} (${t.owner_name})`))].join(', '))}</p><label>Handoff reason <textarea data-field="handoffReason" ${busy ? 'disabled' : ''}>${esc(draft.handoffReason || '')}</textarea></label><button type="button" data-action="owner-handoff-preview" ${busy ? 'disabled' : ''}>Preview owner handoff</button><div data-handoff-preview>${draft.handoffPreview ? `<p>Exact new scope: ${esc(draft.handoffPreview.execution_digest)}</p><pre>${esc(JSON.stringify(draft.handoffPreview.source.owner_handoffs.at(-1), null, 2))}</pre><p>Inspect the new complete scope before saving.</p><pre>${esc(JSON.stringify(draft.handoffPreview.source.tasks, null, 2))}</pre>` : '<p>Preview the exact changed assignment first.</p>'}</div><button type="button" data-action="owner-handoff" ${busy || !draft.handoffPreview ? 'disabled' : ''}>Save review-pending owner handoff</button></details>` : ''}
      ${item.source?.rework ? `<p>Rework of ${esc(item.source.rework.parent_id)}. Invalidated tasks: ${esc(item.source.rework.invalidated_task_ids.join(', '))}. Retained outputs are verified carry-ins. This proposal needs a new review.</p>` : ''}
      ${item.source?.capacity ? `<p>Capacity-scoped proposal from ${esc(item.source.capacity.parent_id)}. New review required. Owner capacities: ${esc(Object.entries(item.source.capacity.owner_limits).map(([owner, limit]) => `${owner}: ${limit}`).join(', '))}. Added owner-lane prerequisites: ${esc(item.source.capacity.added_dependencies.map(d => `${d.task_id} waits for ${d.prerequisite_id}`).join('; '))}.</p>` : ''}
      ${item.status === 'awaiting_import' && !item.source?.capacity && !item.source?.rework ? `<details><summary>Plan owner capacity</summary><p>Limit simultaneous tasks per accountable owner by adding reviewed prerequisite lanes. Values are local to this board, not worker quotas or time estimates. Plan owners and acceptance stay unchanged.</p>${item.source?.specialists ? `<p>Includes every specialist contribution and the retained integration task. Each lane waits for named acceptance; the original integration gate still requires every contribution.</p>` : ''}<label>Capacity per owner JSON <textarea data-field="ownerLimits" rows="3" ${busy ? 'disabled' : ''}>${esc(draft.ownerLimits || JSON.stringify(Object.fromEntries([...new Set((item.tasks || []).map(t => t.owner_id))].map(id => [id, 1]))))}</textarea></label><button type="button" data-action="capacity" ${busy ? 'disabled' : ''}>Create capacity-scoped board</button><p>Original board and source plan are preserved. The new graph needs a new exact review before import; dependent tasks wait for named acceptance.</p></details>` : ''}
      ${item.source?.specialists ? `<p>Specialist delegation from ${esc(item.source.specialists.parent_id)}. Contributions: ${esc(item.source.specialists.contribution_ids.join(', '))}. Original integration gate: ${esc(item.source.specialists.integration_task_id)}. Its owner and acceptance remain unchanged. New exact review required.</p>` : ''}
      ${item.status === 'awaiting_import' && !item.source?.capacity && !item.source?.rework && !item.source?.specialists ? `<details><summary>Delegate specialist contributions</summary><p>Break a broad task into parallel contributions, then integrate their independently reviewed outputs under the original task's owner and acceptance. No authored costs or dates change.</p><label>Integration task <select data-specialist-task ${busy ? 'disabled' : ''}>${(item.tasks || []).map(t => `<option value="${esc(t.task_id)}" ${draft.integrationTask === t.task_id ? 'selected' : ''}>${esc(t.name)}</option>`).join('')}</select></label><p>Available board owners: ${esc([...new Set((item.tasks || []).map(t => `${t.owner_id} (${t.owner_name})`))].join(', '))}</p>${contributions.map((row, index) => `<fieldset><legend>Contribution ${index + 1} · ${esc(row.task_id)}</legend><label>Contribution name <input data-specialist-row="${index}" data-specialist-field="name" value="${esc(row.name)}" maxlength="4096" ${busy ? 'disabled' : ''}></label><label>Accountable owner <select data-specialist-row="${index}" data-specialist-field="owner_id" ${busy ? 'disabled' : ''}>${owners.map(([id, name]) => `<option value="${esc(id)}" ${id === row.owner_id ? 'selected' : ''}>${esc(name)} (${esc(id)})</option>`).join('')}</select></label><label>Acceptance criteria, one per line <textarea data-specialist-row="${index}" data-specialist-field="criteria" rows="3" ${busy ? 'disabled' : ''}>${esc(row.criteria)}</textarea></label><label>Required evidence, one per line <textarea data-specialist-row="${index}" data-specialist-field="evidence" rows="3" ${busy ? 'disabled' : ''}>${esc(row.evidence)}</textarea></label><button type="button" data-action="specialist-remove" data-row="${index}" ${busy || contributions.length <= 2 ? 'disabled' : ''}>Remove contribution ${index + 1}</button></fieldset>`).join('')}<button type="button" data-action="specialist-add" ${busy || contributions.length >= 10 ? 'disabled' : ''}>Add contribution</button><p>Example: “Verify source claims”, acceptance “Every material claim has a checked source”, evidence “Source notes”. Each contribution inherits the original prerequisites. The original task waits for every contribution.</p><button type="button" data-action="specialists" ${busy ? 'disabled' : ''}>Create specialist delegation</button><p>Creates a separate review-pending execution scope. Original board and native plan remain available; no work starts.</p></details>` : ''}
      <ul>${(item.tasks || []).map(t => `<li><strong>${esc(t.name)}</strong> · owner: ${esc(t.owner_name)} (${esc(t.owner_id)})<br>Prerequisites: ${esc(t.dependencies.join(', ') || 'none')}<br>Acceptance: ${esc(t.acceptance_criteria.join('; '))}<br>Required evidence: ${esc(t.required_evidence.join('; '))}<br>Status: ${esc(t.status)}${t.waiting_on?.length ? ` · waiting on ${esc(t.waiting_on.join(', '))}` : ''}${t.blocker ? ` · ${esc(t.blocker)}` : ''}${t.review_id ? `<br>Review: ${esc(t.review_id)} · authority: ${esc(t.reviewer_id)}` : ''}${t.dispatchable || t.reconcilable ? `<br><button type="button" data-action="dispatch" data-task="${esc(t.task_id)}" ${busy ? 'disabled' : ''}>${t.reconcilable ? 'Reconcile same attempt:' : 'Dispatch / reconcile'} ${esc(t.name)}</button>` : ''}</li>`).join('')}</ul>
      <div class="portfolio-buttons"><button type="button" data-action="prepare" ${busy || item.blocker ? 'disabled' : ''}>Import / prepare ready tasks</button><button type="button" data-action="assemble" ${busy || item.status !== 'outputs_reviewed' ? 'disabled' : ''}>Assemble reviewed outputs</button></div>
      <p>MoonFlow controls readiness and attempts. Completion alone does not release dependents: the native named task review must accept the exact output. Unknown dispatches reconcile the same attempt.</p>
      <details><summary>Targeted rework</summary><label>Task to correct <select data-rework-task ${busy ? 'disabled' : ''}>${(item.tasks || []).map(t => `<option value="${esc(t.task_id)}">${esc(t.name)}</option>`).join('')}</select></label><label>Required correction <textarea data-field="reason" rows="3" ${busy ? 'disabled' : ''}>${esc(draft.reason)}</textarea></label><button type="button" data-action="rework" ${busy || item.blocker ? 'disabled' : ''}>Propose correction and dependent rework</button><p>Preserves the old result. The corrected task and all downstream tasks need new outputs and review; unrelated accepted outputs carry forward.</p></details>
      <details><summary>Exact proposed MoonFlow graph</summary><pre>${esc(JSON.stringify(item.graph, null, 2))}</pre></details>` : ''}
    ${assembly ? `<h4>Assembled internal deliverable</h4><p>Customer acceptance, delivery and payment remain separate.</p><textarea readonly rows="18" aria-label="Assembled deliverable text">${esc(assembly)}</textarea><button type="button" data-action="download" ${busy ? 'disabled' : ''}>Download assembled Markdown</button>` : ''}
  </section>`;
}

function downloadMarkdown(text, filename) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/markdown;charset=utf-8' }));
  const a = document.createElement('a'); a.href = url; a.download = filename; a.click(); setTimeout(() => URL.revokeObjectURL(url), 0);
}

export function mountDeliverablePanel(host, { fetcher = fetch, download = downloadMarkdown } = {}) {
  let entries = [], selected = '', busy = false, error = '', notice = '', assembly = '', disposed = false, renderGeneration = 0, operationEpoch = 0;
  const draft = { briefOpen: false, briefOwner: '', briefIncludeSource: false, briefPreview: null, briefBusy: false, handoffTask: '', handoffOwner: '', handoffReason: '', handoffPreview: null, outcome: '', planText: '', workspaceRoot: '', modelSelector: '', reason: '', acceptanceRows: [], planError: '', cancelable: false, ownerLimits: '', specialistRows: null, integrationTask: '', evidenceFiles: [], evidencePreview: null, inspectedEvidence: null };
  function clearBrief() { draft.briefOpen = false; draft.briefOwner = ''; draft.briefIncludeSource = false; draft.briefPreview = null; draft.briefBusy = false; }
  function clearDependencies() { draft.dependencyTask = ''; draft.dependencyIds = []; draft.dependencyReason = ''; draft.dependencyPreview = null; draft.dependencyBusy = false; }
  function clearSourceAssignment() { draft.sourceTask = ''; draft.sourceRefs = []; draft.sourceReason = ''; draft.sourcePreview = null; draft.sourceBusy = false; }
  clearDependencies(); clearSourceAssignment();
  async function refresh() {
    const response = await fetcher('/api/deliverables');
    const value = await response.json();
    if (!response.ok) throw Error(value.error || 'Deliverable host unavailable');
    if (disposed) return;
    clearBrief(); clearDependencies(); clearSourceAssignment(); entries = value.deliverables; if (!selected && entries.length) selected = entries[0].id;
  }
  function setPlan(text) {
    if (draft.planText === text) return;
    draft.planText = text; draft.evidencePreview = null; draft.planError = '';
    draft.evidenceFiles.forEach(file => { file.task_ids = []; });
    try { draft.acceptanceRows = text ? acceptanceRows(text) : []; }
    catch (e) { draft.acceptanceRows = []; draft.planError = e.message; }
  }
  function render() {
    if (disposed) return;
    const generation = ++renderGeneration, renderedSelection = selected;
    const renderedPlan = draft.planText;
    const current = () => !disposed && generation === renderGeneration && selected === renderedSelection;
    host.innerHTML = renderDeliverablePanel({ entries, selected, draft, busy, error, notice, assembly });
    function invalidatePreview() {
      draft.evidencePreview = null;
      const preview = host.querySelector('[data-evidence-preview]');
      if (preview) preview.innerHTML = '<p>Draft changed. Preview the complete mapping again before saving.</p>';
      const save = host.querySelector('[data-action="create"]');
      if (save) save.disabled = true;
    }
    host.querySelectorAll('[data-field]').forEach(field => {
      field.addEventListener('input', e => {
        if (!current() || busy) return;
        if (e.target.dataset.field === 'planText') setPlan(e.target.value);
        else draft[e.target.dataset.field] = e.target.value;
        if (['planText', 'outcome', 'workspaceRoot', 'modelSelector'].includes(e.target.dataset.field)) invalidatePreview();
        if (['handoffTask', 'handoffOwner', 'handoffReason'].includes(e.target.dataset.field)) { draft.handoffPreview = null; const save = host.querySelector('[data-action="owner-handoff"]'); if (save) save.disabled = true; const preview = host.querySelector('[data-handoff-preview]'); if (preview) preview.innerHTML = '<p>Assignment changed. Preview again.</p>'; }
        if (e.target.dataset.field === 'dependencyReason') {
          draft.dependencyPreview = null;
          const save = host.querySelector('[data-action="prerequisites"]'); if (save) save.disabled = true;
          const preview = host.querySelector('[data-dependency-preview]'); if (preview) preview.innerHTML = '<p>Reason changed. Preview again.</p>';
        }
        if (e.target.dataset.field === 'sourceReason') {
          draft.sourcePreview = null;
          const save = host.querySelector('[data-action="source-assignment"]'); if (save) save.disabled = true;
          const preview = host.querySelector('[data-source-preview]'); if (preview) preview.innerHTML = '<p>Reason changed. Preview again.</p>';
        }
      });
      if (field.dataset.field === 'planText') field.addEventListener('change', () => { if (current() && !busy) render(); });
    });
    host.querySelectorAll('[data-acceptance-field]').forEach(field => field.addEventListener('input', e => {
      if (!current() || busy || draft.planText !== renderedPlan) return;
      const row = draft.acceptanceRows.find(row => row.task_id === e.target.dataset.acceptanceTask);
      if (row && ['criteria', 'evidence'].includes(e.target.dataset.acceptanceField)) { row[e.target.dataset.acceptanceField] = e.target.value; invalidatePreview(); }
    }));
    host.querySelector('[data-plan-file]')?.addEventListener('change', async e => {
      if (!current() || busy) return;
      const file = e.target.files?.[0]; if (!file) return;
      const epoch = ++operationEpoch;
      busy = true; draft.cancelable = true; error = ''; notice = ''; render();
      try { const text = await readNativePlanFile(file); if (!disposed && epoch === operationEpoch) setPlan(text); }
      catch (e) { if (!disposed && epoch === operationEpoch) error = e.message; }
      finally { if (epoch === operationEpoch) { busy = false; draft.cancelable = false; render(); } }
    });
    host.querySelector('[data-evidence-files]')?.addEventListener('change', async e => {
      if (!current() || busy) return;
      const files = Array.from(e.target.files || []);
      if (!files.length) return;
      const epoch = ++operationEpoch;
      busy = true; draft.cancelable = true; error = ''; notice = ''; render();
      try { const loaded = await readEvidenceFiles(files); if (!disposed && epoch === operationEpoch) { draft.evidenceFiles = loaded; draft.evidencePreview = null; } }
      catch (e) { if (!disposed && epoch === operationEpoch) error = e.message; }
      finally { if (epoch === operationEpoch) { busy = false; draft.cancelable = false; render(); } }
    });
    host.querySelectorAll('[data-evidence-inspected]').forEach(field => field.addEventListener('change', e => {
      if (!current() || busy) return;
      draft.evidenceFiles[Number(e.target.dataset.evidenceInspected)].inspected = e.target.checked;
      invalidatePreview();
    }));
    host.querySelectorAll('[data-evidence-task]').forEach(field => field.addEventListener('change', e => {
      if (!current() || busy || draft.planText !== renderedPlan) return;
      const file = draft.evidenceFiles[Number(e.target.dataset.evidenceRow)], id = e.target.dataset.evidenceTask;
      file.task_ids = e.target.checked ? [...new Set([...file.task_ids, id])] : file.task_ids.filter(task => task !== id);
      invalidatePreview();
    }));
    host.querySelector('[data-brief-owner]')?.addEventListener('change', e => {
      if (!current() || busy) return;
      draft.briefOpen = true; draft.briefOwner = e.target.value; draft.briefPreview = null; notice = ''; error = ''; render();
    });
    host.querySelector('[data-brief-source]')?.addEventListener('change', e => {
      if (!current() || busy) return;
      draft.briefOpen = true; draft.briefIncludeSource = e.target.checked; draft.briefPreview = null; notice = ''; error = ''; render();
    });
    host.querySelector('[data-select]')?.addEventListener('change', e => { if (!current() || busy) return; selected = e.target.value; clearBrief(); clearDependencies(); clearSourceAssignment(); draft.handoffPreview = null; draft.handoffTask = ''; draft.handoffOwner = ''; draft.handoffReason = ''; draft.ownerLimits = ''; draft.specialistRows = null; draft.integrationTask = ''; draft.inspectedEvidence = null; assembly = ''; error = ''; notice = ''; render(); });
    host.querySelector('[data-source-task]')?.addEventListener('change', e => {
      if (!current() || busy) return;
      clearSourceAssignment(); draft.sourceTask = e.target.value;
      draft.sourceRefs = (entries.find(item => item.id === selected)?.source?.local_evidence?.files || []).filter(file => file.task_ids.includes(draft.sourceTask)).map(file => file.artifact_ref);
      error = ''; notice = ''; render();
    });
    host.querySelectorAll('[data-source-ref]').forEach(field => field.addEventListener('change', e => {
      if (!current() || busy) return;
      const ref = e.target.dataset.sourceRef;
      draft.sourceRefs = e.target.checked ? [...new Set([...draft.sourceRefs, ref])] : draft.sourceRefs.filter(value => value !== ref);
      draft.sourcePreview = null; notice = ''; error = ''; render();
    }));
    host.querySelector('[data-dependency-task]')?.addEventListener('change', e => {
      if (!current() || busy) return;
      clearDependencies(); draft.dependencyTask = e.target.value;
      draft.dependencyIds = [...(entries.find(item => item.id === selected)?.tasks.find(task => task.task_id === e.target.value)?.dependencies || [])];
      error = ''; notice = ''; render();
    });
    host.querySelectorAll('[data-dependency-prerequisite]').forEach(field => field.addEventListener('change', e => {
      if (!current() || busy) return;
      const id = e.target.dataset.dependencyPrerequisite;
      draft.dependencyIds = e.target.checked ? [...new Set([...draft.dependencyIds, id])] : draft.dependencyIds.filter(value => value !== id);
      draft.dependencyPreview = null; notice = ''; error = ''; render();
    }));
    host.querySelectorAll('[data-specialist-field]').forEach(field => field.addEventListener(field.dataset.specialistField === 'owner_id' ? 'change' : 'input', e => {
      if (!current() || busy) return;
      draft.specialistRows ||= specialistRows(entries.find(item => item.id === selected));
      const row = draft.specialistRows[Number(e.target.dataset.specialistRow)];
      if (row) row[e.target.dataset.specialistField] = e.target.value;
    }));
    host.querySelector('[data-specialist-task]')?.addEventListener('change', e => { if (current() && !busy) draft.integrationTask = e.target.value; });
    host.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', async () => {
      if (!current()) return;
      const action = button.dataset.action;
      if (action === 'source-assignment-cancel') {
        if (busy && !draft.sourceBusy) return;
        ++operationEpoch; busy = false; draft.cancelable = false; clearSourceAssignment();
        error = ''; notice = 'Source assignment draft cancelled. Saved boards remain available.'; render(); return;
      }
      if (action === 'prerequisites-cancel') {
        if (busy && !draft.dependencyBusy) return;
        ++operationEpoch; busy = false; draft.cancelable = false; clearDependencies();
        error = ''; notice = 'Prerequisite draft cancelled. Saved boards remain available.'; render(); return;
      }
      if (action === 'brief-cancel') {
        if (busy && !draft.briefBusy) return;
        ++operationEpoch; busy = false; draft.cancelable = false; clearBrief();
        error = ''; notice = ''; render(); return;
      }
      if (action === 'cancel-draft') {
        if (busy && !draft.cancelable) return;
        ++operationEpoch; busy = false; draft.cancelable = false; clearBrief(); clearDependencies(); clearSourceAssignment();
        setPlan(''); draft.evidenceFiles = []; draft.evidencePreview = null;
        draft.handoffTask = ''; draft.handoffOwner = ''; draft.handoffReason = ''; draft.handoffPreview = null;
        draft.outcome = ''; draft.workspaceRoot = ''; draft.modelSelector = '';
        error = ''; notice = 'Unsaved task draft cancelled. Saved boards remain available.'; render(); return;
      }
      if (busy) return;
      if (action === 'brief-preview' || action === 'brief-download') {
        draft.briefOpen = true;
        const item = entries.find(item => item.id === selected), prior = draft.briefPreview;
        if (!item?.execution_digest || !draft.briefOwner || (action === 'brief-download' && !prior)) {
          error = 'Choose an owner and preview this exact brief before downloading'; render(); return;
        }
        const body = { id: selected, ownerId: draft.briefOwner, executionDigest: item.execution_digest,
          includeSourceText: draft.briefIncludeSource, ...(action === 'brief-download' ? { packetDigest: prior.content_digest } : {}) };
        const epoch = ++operationEpoch;
        draft.briefPreview = null; busy = true; draft.briefBusy = true; draft.cancelable = true; error = ''; notice = ''; render();
        try {
          const response = await fetcher('/api/deliverables/delegation-brief', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
          const brief = await response.json();
          if (disposed || epoch !== operationEpoch) return;
          if (!response.ok) throw Error(brief.error || `HTTP ${response.status}`);
          if (brief.id !== body.id || brief.owner_id !== body.ownerId || brief.execution_digest !== body.executionDigest || brief.source_text_included !== body.includeSourceText || (prior && action === 'brief-download' && brief.content_digest !== prior.content_digest)) throw Error('Owner brief response changed; preview again');
          draft.briefPreview = brief;
          if (action === 'brief-download') { download(brief.text, brief.filename); notice = 'Owner brief downloaded locally. Nothing was sent and no work started.'; }
          else notice = 'Owner brief ready to inspect. Download will reverify saved source bytes.';
        } catch (e) { if (!disposed && epoch === operationEpoch) error = e.message; }
        finally { if (!disposed && epoch === operationEpoch) { busy = false; draft.briefBusy = false; draft.cancelable = false; render(); } }
        return;
      }
      if (action === 'evidence-remove') { draft.evidenceFiles.splice(Number(button.dataset.row), 1); draft.evidencePreview = null; render(); return; }
      if (action === 'specialist-add' || action === 'specialist-remove') {
        const item = entries.find(item => item.id === selected);
        draft.specialistRows ||= specialistRows(item);
        if (action === 'specialist-add' && draft.specialistRows.length < 10) draft.specialistRows.push(...specialistRows(item, 1, draft.specialistRows));
        if (action === 'specialist-remove' && draft.specialistRows.length > 2) draft.specialistRows.splice(Number(button.dataset.row), 1);
        render(); return;
      }
      if (action === 'download') {
        const url = URL.createObjectURL(new Blob([assembly], { type: 'text/markdown;charset=utf-8' }));
        const a = document.createElement('a'); a.href = url; a.download = `${selected}.md`; a.click(); setTimeout(() => URL.revokeObjectURL(url), 0); return;
      }
      let taskCriteria;
      if (action === 'create' || action === 'preview') { try { if (draft.planError) throw Error(draft.planError); taskCriteria = acceptanceMap(draft.acceptanceRows); } catch (e) { error = e.message; render(); return; } }
      if ((action === 'create' || action === 'preview') && draft.evidenceFiles.length) {
        if (draft.evidenceFiles.some(file => !file.inspected || !file.task_ids.length)) { error = 'Inspect each source and assign it to at least one named task'; render(); return; }
      }
      if (action === 'create' && !draft.evidencePreview) { error = 'Preview the complete task board and source/task mapping before saving'; render(); return; }
      let specialists;
      if (action === 'specialists') {
        const rows = draft.specialistRows || specialistRows(entries.find(item => item.id === selected));
        const lines = text => text.split('\n').map(line => line.trim()).filter(Boolean);
        specialists = rows.map(row => ({ task_id: row.task_id, name: row.name.trim(), owner_id: row.owner_id, acceptance_criteria: lines(row.criteria), required_evidence: lines(row.evidence) }));
        if (specialists.some(row => !row.name || !row.owner_id || !row.acceptance_criteria.length || !row.required_evidence.length)) { error = 'Every contribution needs a name, owner, acceptance criteria and required evidence'; render(); return; }
      }
      let ownerLimits;
      if (action === 'capacity') { try { ownerLimits = JSON.parse(draft.ownerLimits || host.querySelector('[data-field="ownerLimits"]')?.value || '{}'); } catch { error = 'Owner capacities must be a JSON object'; render(); return; } }
      if (action === 'owner-handoff' && !draft.handoffPreview) { error = 'Preview this exact owner handoff before saving'; render(); return; }
      if (action === 'prerequisites' && !draft.dependencyPreview) { error = 'Preview this exact prerequisite revision before saving'; render(); return; }
      if (action === 'source-assignment' && !draft.sourcePreview) { error = 'Preview this exact source assignment before saving'; render(); return; }
      const body = action.startsWith('source-assignment') ? { id: selected, taskId: draft.sourceTask, artifactRefs: [...draft.sourceRefs], reason: draft.sourceReason, executionDigest: entries.find(item => item.id === selected)?.execution_digest, previewDigest: draft.sourcePreview?.execution_digest } : action.startsWith('prerequisites') ? { id: selected, taskId: draft.dependencyTask, dependencies: [...draft.dependencyIds], reason: draft.dependencyReason, executionDigest: entries.find(item => item.id === selected)?.execution_digest, previewDigest: draft.dependencyPreview?.execution_digest } : action.startsWith('owner-handoff') ? { id: selected, taskId: draft.handoffTask, ownerId: draft.handoffOwner, reason: draft.handoffReason, previewDigest: draft.handoffPreview?.execution_digest } : action === 'create' || action === 'preview' ? { taskCriteria, planText: draft.planText, outcome: draft.outcome, workspaceRoot: draft.workspaceRoot, modelSelector: draft.modelSelector, evidenceFiles: draft.evidenceFiles.map(({ name, content_base64, task_ids }) => ({ name, content_base64, task_ids })), previewDigest: draft.evidencePreview?.execution_digest } :
        { id: selected, artifactRef: button.dataset.artifact, ownerLimits, specialists, taskId: action === 'specialists' ? (draft.integrationTask || host.querySelector('[data-specialist-task]')?.value) : button.dataset.task || host.querySelector('[data-rework-task]')?.value, reason: draft.reason };
      const requestText = JSON.stringify(body);
      if (requestText.length > 1000000) { error = 'Reduce the plan, task acceptance or local evidence to fit the host request limit (1,000,000 characters)'; render(); return; }
      const epoch = ++operationEpoch;
      if (action === 'owner-handoff-preview') draft.handoffPreview = null;
      if (action === 'prerequisites-preview') draft.dependencyPreview = null;
      draft.dependencyBusy = action === 'prerequisites-preview';
      if (action === 'source-assignment-preview') draft.sourcePreview = null;
      draft.sourceBusy = action === 'source-assignment-preview';
      busy = true; draft.cancelable = action === 'preview' || action === 'owner-handoff-preview' || action === 'prerequisites-preview' || action === 'source-assignment-preview'; error = ''; notice = ''; render();
      try {
        if (action === 'refresh') await refresh();
        else {
          const response = await fetcher(`/api/deliverables/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: requestText });
          const value = await response.json();
          if (!response.ok) throw Error(value.error || `HTTP ${response.status}`);
          if (disposed || epoch !== operationEpoch) return;
          if (action === 'source-assignment-preview') { draft.sourcePreview = value; notice = 'Source assignment ready to inspect. No board has been saved.'; return; }
          if (action === 'prerequisites-preview') { draft.dependencyPreview = value; notice = 'Prerequisite revision ready to inspect. No board has been saved.'; return; }
          if (action === 'owner-handoff-preview') { draft.handoffPreview = value; notice = 'Owner handoff ready to inspect. No board has been saved.'; return; }
          if (action === 'preview') { draft.evidencePreview = value; notice = 'Exact mapping ready to inspect. Nothing has been saved or executed.'; return; }
          if (action === 'inspect-evidence') { draft.inspectedEvidence = value.evidence; return; }
          selected = value.id; clearBrief(); draft.handoffPreview = null; draft.handoffTask = ''; draft.handoffOwner = ''; draft.handoffReason = ''; draft.inspectedEvidence = null; draft.ownerLimits = ''; draft.specialistRows = null; draft.integrationTask = ''; assembly = value.text || '';
          notice = action === 'dispatch' ? `Dispatch: ${value.dispatch?.status || 'unresolved'}. ${value.dispatch?.blocker || 'Refresh after native review to release dependents.'}` :
            action === 'source-assignment' ? 'Source assignment saved as a separate review-pending board. Its parent review cannot authorize the changed task inputs.' :
            action === 'prerequisites' ? 'Prerequisite revision saved as a separate review-pending board. Its parent review cannot authorize the changed graph.' :
            action === 'owner-handoff' ? 'Owner handoff saved as a separate review-pending board. No work has started.' :
            action === 'specialists' ? 'Specialist scope saved. Review each contribution and the retained integration gate before import. Nothing has executed.' :
            action === 'capacity' ? 'Capacity-scoped board saved. Review its added prerequisites and new digest before import. Nothing has executed.' :
            action === 'rework' ? 'Correction proposal saved. The old deliverable is unchanged; review the new exact scope before import.' :
            action === 'create' ? 'Task board saved. Nothing has executed.' : action === 'assemble' ? 'Exact reviewed output bytes assembled.' : 'Native graph state refreshed. No provider call was made.';
          await refresh();
        }
      } catch (e) { if (!disposed && epoch === operationEpoch) error = e.message; }
      finally { if (epoch === operationEpoch) { busy = false; draft.cancelable = false; draft.dependencyBusy = false; draft.sourceBusy = false; render(); } }
    }));
  }
  render(); refresh().then(render).catch(e => { if (!disposed) { error = `Deliverable host disconnected: ${e.message}`; render(); } });
  return () => { disposed = true; };
}

if (typeof document !== 'undefined') {
  let owner = null, panel = null, dispose = null;
  const observe = () => {
    const host = document.getElementById('portfolio-home');
    if (host === owner) return;
    dispose?.(); panel?.remove(); owner = host;
    if (host) { panel = document.createElement('div'); panel.className = 'portfolio-home'; host.after(panel); dispose = mountDeliverablePanel(panel); }
  };
  new MutationObserver(observe).observe(document.documentElement, { childList: true, subtree: true });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', observe); else observe();
}
