import path from 'node:path';
import { delegationBrief } from './delegation_brief.mjs';
import { readFile, writeFile, mkdir, readdir, realpath, lstat, rename } from 'node:fs/promises';
import { compileDeliverable, normalizeLocalEvidence, verifyDeliverable, verifyApproval, projectDeliverable, prepareInvocation, proposeRework, proposeCapacity, proposeSpecialists, proposeOwnerHandoff, proposeDependencyRevision, proposeEvidenceAssignment, withCarriedArtifacts, artifactRef, identifier, json, sha } from './deliverable_workflow.mjs';
import { dispatchCapability, capabilityGateway, assertCapabilityReceipt } from './portfolio_dispatch.mjs';

async function immutable(file, value) {
  await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const bytes = typeof value === 'string' || Buffer.isBuffer(value) ? value : json(value);
  try { await writeFile(file, bytes, { flag: 'wx', mode: 0o600 }); }
  catch (error) { if (error.code !== 'EEXIST' || !Buffer.from(await readFile(file)).equals(Buffer.from(bytes))) throw Error(`Existing deliverable file differs: ${path.basename(file)}`); }
}
async function atomicJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.tmp`;
  await writeFile(temporary, json(value), { mode: 0o600 }); await rename(temporary, file);
}
async function readJson(file, optional = false) {
  try { return JSON.parse(await readFile(file, 'utf8')); }
  catch (error) { if (optional && error.code === 'ENOENT') return null; throw error; }
}
// Read only regular files beneath the exact run; never follow an artifact symlink.
async function bytesAt(root, ref) {
  if (!artifactRef(ref)) throw Error('Unsafe deliverable artifact reference');
  const file = path.join(root, ref), canonicalRoot = await realpath(root);
  if (await realpath(file) !== path.join(canonicalRoot, ref)) throw Error('Deliverable artifact symlink is not allowed');
  const stat = await lstat(file);
  if (!stat.isFile() || stat.size > 2_000_000) throw Error('Artifact missing, nonregular or above the 2 MB assembly limit');
  return readFile(file);
}
const projectionRef = id => `.moonsuite/products/moonflow/runs/${id}/projection.json`;

// For source remapping, any retained native marker means reconcile first.
// Presence is independent of valid JSON: null, malformed or nonregular markers
// cannot turn uncertain/imported work back into a never-started proposal.
async function hasNativeState(root, id) {
  for (const ref of [projectionRef(id), 'runtime/prepare-intent.json']) {
    try { await lstat(path.join(root, ref)); return true; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return false;
}

export async function reviewedOutputs(root, handoff, projection, taskIds = handoff.source.tasks.map(t => t.task_id)) {
  const state = projectDeliverable(handoff, projection), results = [];
  let totalBytes = 0;
  for (const taskId of taskIds) {
    const task = state.tasks.find(t => t.task_id === taskId);
    if (!task?.accepted) throw Error(`Task output has not passed named review: ${taskId}`);
    const invocation = await readJson(path.join(root, 'runtime', taskId, 'invocation.json'));
    const receipt = assertCapabilityReceipt(invocation, await readJson(path.join(root, 'runtime', taskId, 'receipt.json')));
    if (receipt.status !== 'succeeded' || receipt.request_id !== task.request_id || receipt.attempt_id !== task.attempt_id ||
      receipt.result_id !== task.result_id || receipt.output_digest !== task.output_digest ||
      !Array.isArray(receipt.output_artifacts) || !receipt.output_artifacts.length ||
      new Set(receipt.output_artifacts).size !== receipt.output_artifacts.length ||
      receipt.output_artifacts.some(ref => !task.artifacts.includes(ref))) throw Error('Output receipt does not match the reviewed task');
    const artifacts = [];
    for (const ref of receipt.output_artifacts) {
      const bytes = await bytesAt(root, ref);
      totalBytes += bytes.length;
      if (totalBytes > 8_000_000) throw Error('Reviewed outputs exceed the 8 MB assembly limit');
      artifacts.push({ ref, digest: sha(bytes), bytes });
    }
    if (sha(artifacts.map(a => `${a.ref}|${a.digest}`).join('\n')) !== task.output_digest) throw Error(`Reviewed output bytes changed: ${taskId}`);
    const review = JSON.parse((await bytesAt(root, task.review_artifact)).toString('utf8'));
    const declared = handoff.graph.items.find(i => i.work_item_id === taskId);
    if (review.contract_id !== 'moonflow.acceptance-review.v1' || review.decision !== 'accepted' ||
      review.run_id !== handoff.id || review.work_item_id !== taskId || review.declaration_id !== declared.declaration_id ||
      review.review_id !== task.review_id || typeof review.reviewer_id !== 'string' || !review.reviewer_id.trim() || review.review_authority_id !== task.reviewer_id || review.receipt_artifact !== task.review_artifact ||
      review.result_id !== task.result_id || review.attempt_id !== task.attempt_id || review.output_digest !== task.output_digest ||
      !Array.isArray(review.criteria) || review.criteria.length !== task.acceptance_criteria.length ||
      review.criteria.some((criterion, i) => criterion.criterion !== task.acceptance_criteria[i] || criterion.satisfied !== true ||
        !Array.isArray(criterion.evidence_refs) || !criterion.evidence_refs.length || criterion.evidence_refs.some(ref => !receipt.output_artifacts.includes(ref)))) throw Error('Named review does not match the exact output and criteria');
    // The installed agent-goal adapter returns receipt + journal, not arbitrary
    // output paths. Follow only content-digested evidence inside that exact
    // accepted receipt, and retain the native receipt identity as provenance.
    const content = [];
    for (const envelope of artifacts) {
      if (!envelope.ref.endsWith('.json')) continue;
      let goal; try { goal = JSON.parse(envelope.bytes.toString('utf8')); } catch { continue; }
      if (goal.contract_id !== 'moonclaw.agent-goal-execution-receipt.v1') continue;
      const request = handoff.requests[`inputs/${taskId}.json`];
      if (goal.operation_ref !== 'moonclaw/agent.goal.execute@0.1.5' || goal.execution_status !== 'succeeded' ||
        goal.goal_outcome !== 'achieved' || goal.acceptance_status !== 'review-required' ||
        goal.session_id !== request.session_id || goal.goal_id !== request.goal_id || goal.receipt_ref !== envelope.ref ||
        !Array.isArray(goal.artifact_evidence) || !goal.artifact_evidence.length ||
        new Set(goal.artifact_evidence.map(a => a.ref)).size !== goal.artifact_evidence.length) throw Error('Agent goal receipt does not match the reviewed task');
      for (const evidence of goal.artifact_evidence) {
        if (!/^sha256:[a-f0-9]{64}$/.test(evidence.digest)) throw Error('Agent evidence lacks a content digest');
        const bytes = await bytesAt(root, evidence.ref);
        if (sha(bytes) !== evidence.digest) throw Error(`Reviewed output bytes changed: ${taskId}`);
        totalBytes += bytes.length;
        if (totalBytes > 8_000_000) throw Error('Reviewed outputs exceed the 8 MB assembly limit');
        if (evidence.ref !== goal.journal_ref && evidence.ref !== goal.receipt_ref) content.push({ ref: evidence.ref, digest: evidence.digest, bytes, receipt_ref: envelope.ref });
      }
    }
    if (!content.length) throw Error(`Reviewed goal has no content-digested deliverable artifacts: ${taskId}`);
    results.push({ task: { ...task, reviewer_id: review.reviewer_id, review_authority_id: review.review_authority_id }, artifacts: content, review });
  }
  return results;
}

export function createDeliverableHost({ data, config, readOperatorJson, runMoonflow, now = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), gatewayFactory = capabilityGateway }) {
  const base = path.join(data, 'deliverables'), busy = new Set();
  const rootFor = id => { if (!/^deliverable-[a-f0-9]{24}$/.test(id)) throw Error('Invalid deliverable id'); return path.join(base, id); };
  async function load(id) { return verifyDeliverable(await readJson(path.join(rootFor(id), 'handoff.json'))); }
  async function projection(id) { return readJson(path.join(rootFor(id), projectionRef(id)), true); }
  async function persist(handoff) {
    const root = rootFor(handoff.id);
    await immutable(path.join(root, 'handoff.json'), handoff);
    await immutable(path.join(root, 'inputs/deliverable-scope.json'), handoff.source);
    for (const [ref, value] of Object.entries(handoff.requests)) await immutable(path.join(root, ref), value);
    await immutable(path.join(root, 'flow/work-graph.json'), handoff.graph);
    return handoff;
  }
  async function evidenceBytes(root, handoff) {
    const bytes = new Map();
    for (const file of handoff.source.local_evidence?.files || []) {
      const content = await bytesAt(root, file.artifact_ref);
      if (content.length !== file.byte_length || sha(content) !== file.digest) throw Error(`Local evidence bytes changed: ${file.name}`);
      bytes.set(file.artifact_ref, content);
    }
    return bytes;
  }
  async function persistEvidence(root, handoff, bytes) {
    if (!handoff.source.local_evidence) return;
    await mkdir(root, { recursive: true, mode: 0o700 });
    if (!(await lstat(root)).isDirectory()) throw Error('Evidence run directory must not be a symlink');
    const canonicalRoot = await realpath(root);
    for (const ref of ['inputs', 'inputs/local-evidence']) {
      const directory = path.join(root, ref);
      try { await mkdir(directory, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
      if (!(await lstat(directory)).isDirectory() || await realpath(directory) !== path.join(canonicalRoot, ref)) throw Error('Evidence directory symlinks are not allowed');
    }
    for (const file of handoff.source.local_evidence.files) {
      const content = bytes.get(file.artifact_ref);
      if (!content || content.length !== file.byte_length || sha(content) !== file.digest) throw Error('Evidence bytes do not match the exact scope');
      const destination = path.join(root, file.artifact_ref);
      try { if (!(await lstat(destination)).isFile()) throw Error('Evidence destination must be a regular file'); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      await immutable(destination, content);
    }
  }
  async function approval(handoff, provider = false) {
    const settings = await config();
    if (!settings?.deliverable_review_file || !path.isAbsolute(settings.deliverable_review_file)) throw Error('Configure an exact deliverable_review_file before native execution');
    if (settings.workspace_root !== handoff.source.workspace_root || settings.model_selector !== handoff.source.model_selector) throw Error('Configured workspace or model differs from this reviewed scope');
    const relative = path.relative(settings.workspace_root, rootFor(handoff.id));
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw Error('Deliverable data must be beneath the approved workspace so agents can read prerequisite outputs');
    const review = verifyApproval(handoff, await readOperatorJson(settings.deliverable_review_file), provider);
    return { settings, review };
  }
  async function catalogSnapshot(root, handoff, settings, evaluatedAt) {
    if (!path.isAbsolute(settings.moonflow_binary || '') || !path.isAbsolute(settings.catalog_file || '')) throw Error('Configured MoonFlow binary and capability catalog are required');
    const catalog = await readOperatorJson(settings.catalog_file), digest = sha(json(catalog));
    const ref = `flow/catalogs/${digest.slice(7)}.json`;
    await immutable(path.join(root, ref), catalog);
    const report = await runMoonflow(settings.moonflow_binary, ['validate-work-graph-capabilities', path.join(root, 'flow/work-graph.json'), path.join(root, ref), evaluatedAt]);
    const expected = handoff.graph.items.map(item => ({ work_item_id: item.work_item_id, operation_ref: item.operation,
      adapter_id: 'moonclaw-agent-goal-v1', input_schema_ref: item.input_contracts[0], output_schema_ref: item.output_contracts[0],
      authority: item.requested_authority, claim_ceiling: item.required_claim, review_required: true }));
    if (report.contract_id !== 'moonflow.graph-capability-report.v1' || report.graph_id !== handoff.id ||
      report.catalog_id !== catalog.catalog_id || report.accepted !== true || !Array.isArray(report.bindings) || report.bindings.length !== expected.length ||
      new Set(report.bindings.map(binding => binding.work_item_id)).size !== expected.length ||
      expected.some(binding => { const actual = report.bindings.find(b => b.work_item_id === binding.work_item_id); return !actual || Object.keys(binding).some(key => actual[key] !== binding[key]); })) throw Error('Current capability catalog does not validate the exact reviewed graph and authority');
    return { catalog, ref, digest, evaluated_at: evaluatedAt };
  }
  async function finishPreparation(root, handoff) {
    const intent = await readJson(path.join(root, 'runtime/prepare-intent.json'), true);
    if (!intent) return;
    if (intent.run_id !== handoff.id || !artifactRef(intent.catalog_ref) || !Array.isArray(intent.before_request_ids)) throw Error('Preparation catalog identity changed');
    const catalog = await readJson(path.join(root, intent.catalog_ref));
    if (sha(json(catalog)) !== intent.catalog_digest) throw Error('Preparation catalog bytes changed');
    const current = await projection(handoff.id);
    if (!current) return;
    for (const task of projectDeliverable(handoff, current).tasks) if (task.request_id && !intent.before_request_ids.includes(task.request_id)) {
      const request = await readJson(path.join(root, `.moonsuite/products/moonflow/runs/${handoff.id}/dispatch/${task.request_id}.request.json`));
      if (request.created_at !== intent.evaluated_at) throw Error('Prepared request does not match its catalog evaluation');
      await immutable(path.join(root, 'runtime/catalogs', `${task.request_id}.json`), { request_id: task.request_id, catalog_ref: intent.catalog_ref, catalog_digest: intent.catalog_digest, evaluated_at: intent.evaluated_at });
    }
  }
  async function state(id) {
    const handoff = await load(id), result = projectDeliverable(handoff, await projection(id));
    await evidenceBytes(rootFor(id), handoff);
    return { ...result, execution_digest: handoff.execution_digest, source: handoff.source, graph: handoff.graph,
      assembled: Boolean(await readJson(path.join(rootFor(id), 'assembly.json'), true)) };
  }
  async function list() {
    await mkdir(base, { recursive: true, mode: 0o700 });
    const result = [];
    for (const entry of await readdir(base, { withFileTypes: true })) if (entry.isDirectory() && /^deliverable-[a-f0-9]{24}$/.test(entry.name)) {
      try { result.push(await state(entry.name)); } catch (error) { result.push({ id: entry.name, status: 'verification_blocked', blocker: error.message }); }
    }
    return result;
  }
  async function act(action, body) {
    if (action === 'create' || action === 'preview') {
      const handoff = compileDeliverable({ planText: body.planText, outcome: body.outcome, workspaceRoot: body.workspaceRoot, modelSelector: body.modelSelector, recordedAt: now(), artifactRoot: base, taskCriteria: body.taskCriteria || {}, evidenceFiles: body.evidenceFiles === undefined ? [] : body.evidenceFiles });
      if (action === 'preview') return { ...projectDeliverable(handoff, null), source: handoff.source, graph: handoff.graph, execution_digest: handoff.execution_digest, preview: true };
      if ((handoff.source.local_evidence || body.previewDigest !== undefined) && body.previewDigest !== handoff.execution_digest) throw Error('Preview this exact task board and source/task mapping before saving');
      const root = rootFor(handoff.id);
      const existing = await readJson(path.join(root, 'handoff.json'), true);
      if (existing) verifyDeliverable(existing);
      const evidence = normalizeLocalEvidence(body.evidenceFiles || [], handoff.source.tasks);
      await persistEvidence(root, handoff, evidence.bytes);
      await immutable(path.join(root, 'source-plan.json'), body.planText);
      await persist(existing || handoff); return state(handoff.id);
    }
    const id = body.id, root = rootFor(id);
    if (busy.has(id)) throw Error('This deliverable already has an operation in progress; refresh before retrying');
    busy.add(id);
    try {
      const handoff = await load(id);
      if (action === 'delegation-brief') {
        if (sha(await bytesAt(root, 'source-plan.json')) !== handoff.source.plan_digest) throw Error('Source plan bytes changed');
        let carriedBytes = 0;
        for (const record of handoff.source.rework?.carried_artifacts || []) {
          const bytes = await bytesAt(root, record.artifact_ref);
          if (sha(bytes) !== record.digest) throw Error('Retained output changed');
          if ((carriedBytes += bytes.length) > 8_000_000) throw Error('Retained evidence exceeds the 8 MB verification limit');
        }
        const brief = delegationBrief({ handoff, ownerId: body.ownerId, executionDigest: body.executionDigest,
          includeSourceText: body.includeSourceText, evidenceBytes: await evidenceBytes(root, handoff) });
        if (body.packetDigest !== undefined && body.packetDigest !== brief.content_digest) throw Error('Preview this exact owner brief again before downloading');
        return brief;
      }
      if (action === 'inspect-evidence') {
        const file = handoff.source.local_evidence?.files.find(file => file.artifact_ref === body.artifactRef);
        if (!file) throw Error('Choose a declared local evidence file');
        const bytes = (await evidenceBytes(root, handoff)).get(file.artifact_ref);
        return { id, evidence: { ...file, text: new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes) } };
      }
      if (action === 'prepare' || action === 'dispatch') {
        await evidenceBytes(root, handoff);
        if (sha(await bytesAt(root, 'source-plan.json')) !== handoff.source.plan_digest) throw Error('Source plan bytes changed');
        const control = await readJson(path.join(root, `.moonsuite/products/moonflow/runs/${id}/control.json`), true);
        if (control && (control.contract_id !== 'moonflow.run-control.v1' || control.run_id !== id || control.state !== 'running' ||
          !['', 'workspace-mutation', 'external-effect', 'physical-effect'].includes(control.authority_ceiling))) throw Error('MoonFlow run control blocks this operation');
      }
      if (action === 'prepare') {
        const { settings } = await approval(handoff);
        await finishPreparation(root, handoff);
        const selected = await catalogSnapshot(root, handoff, settings, now());
        if (!await projection(id)) await runMoonflow(settings.moonflow_binary, ['import-conformant-graph', root, path.join(root, 'flow/work-graph.json'), path.join(root, selected.ref), selected.evaluated_at]);
        const before = await projection(id);
        const accepted = projectDeliverable(handoff, before).tasks.filter(t => t.accepted).map(t => t.task_id);
        await reviewedOutputs(root, handoff, before, accepted);
        await atomicJson(path.join(root, 'runtime/prepare-intent.json'), { run_id: id, catalog_ref: selected.ref, catalog_digest: selected.digest,
          evaluated_at: selected.evaluated_at, before_request_ids: before.items.map(i => i.request_id).filter(Boolean) });
        await runMoonflow(settings.moonflow_binary, ['prepare-next', root, id, selected.ref, selected.evaluated_at]);
        await finishPreparation(root, handoff);
        await atomicJson(path.join(root, 'flow/capability-catalog.json'), selected.catalog);
        return state(id);
      }
      if (action === 'dispatch') {
        const { settings, review } = await approval(handoff, true);
        if (settings.moonclaw_workspace_root !== root) throw Error('MoonClaw gateway must be configured to serve this exact deliverable root');
        const current = await projection(id), task = projectDeliverable(handoff, current).tasks.find(t => t.task_id === body.taskId);
        if (!task?.dispatchable && !task?.reconcilable) throw Error('Choose an active MoonFlow-prepared task or a blocked unknown attempt to reconcile');
        await reviewedOutputs(root, handoff, current, task.dependencies);
        const preparedRequest = await readJson(path.join(root, `.moonsuite/products/moonflow/runs/${id}/dispatch/${task.request_id}.request.json`));
        const candidate = prepareInvocation({ handoff, projection: current, taskId: task.task_id, preparedRequest, approval: review, recordedAt: now() });
        const inputParts = [];
        for (const ref of preparedRequest.input_artifacts) inputParts.push(`${ref}|${sha(await bytesAt(root, ref))}`);
        if (sha(inputParts.join('\n')) !== preparedRequest.input_digest) throw Error('Prepared input bytes changed; do not dispatch this attempt');
        // Reuse original timestamps and content after an uncertain submit.
        const invocationFile = path.join(root, 'runtime', task.task_id, 'invocation.json');
        const prior = await readJson(invocationFile, true);
        if (prior && (json(prior.request) !== json(candidate.request) || json(prior.input) !== json(candidate.input) || json(prior.config) !== json(candidate.config))) throw Error('Prior invocation changed; reconcile the original attempt');
        let invocation = prior || candidate;
        const invocationCatalogFile = path.join(root, 'runtime', task.task_id, 'invocation-catalog.json');
        const invocationSnapshots = path.join(root, 'runtime', task.task_id, 'invocations');
        const catalogSnapshots = path.join(root, 'runtime', task.task_id, 'invocation-catalogs');
        const previousCatalog = (prior && await readJson(path.join(catalogSnapshots, `${sha(json(prior)).slice(7)}.json`), true)) || await readJson(invocationCatalogFile, true);
        let selected;
        if (previousCatalog) {
          if (prior && previousCatalog.evaluated_at !== prior.evaluated_at) throw Error('Invocation evaluation time changed');
          if (!prior) invocation = { ...candidate, evaluated_at: previousCatalog.evaluated_at, recorded_at: previousCatalog.evaluated_at };
          if (!artifactRef(previousCatalog.catalog_ref)) throw Error('Unsafe invocation catalog reference');
          const catalog = await readJson(path.join(root, previousCatalog.catalog_ref));
          if (sha(json(catalog)) !== previousCatalog.catalog_digest || previousCatalog.request_id !== task.request_id) throw Error('Invocation catalog identity changed');
          selected = { catalog, ref: previousCatalog.catalog_ref, digest: previousCatalog.catalog_digest };
        } else {
          selected = await catalogSnapshot(root, handoff, settings, invocation.evaluated_at);
          await immutable(invocationCatalogFile, { request_id: task.request_id, catalog_ref: selected.ref, catalog_digest: selected.digest, evaluated_at: invocation.evaluated_at });
        }
        const originalCatalogRecord = { request_id: task.request_id, catalog_ref: selected.ref, catalog_digest: selected.digest, evaluated_at: invocation.evaluated_at };
        await immutable(path.join(invocationSnapshots, `${sha(json(invocation)).slice(7)}.json`), invocation);
        await immutable(path.join(catalogSnapshots, `${sha(json(invocation)).slice(7)}.json`), originalCatalogRecord);
        await immutable(invocationFile, invocation);
        // Restore the exact invocation's catalog for status/reconcile. New health
        // may prepare later work without rewriting an uncertain attempt's evidence.
        await atomicJson(path.join(root, 'flow/capability-catalog.json'), selected.catalog);
        const result = await dispatchCapability({ invocation, reconcileOnly: task.reconcilable,
          journalPath: path.join(root, 'runtime', task.task_id, 'journal.json'), receiptPath: path.join(root, 'runtime', task.task_id, 'receipt.json'),
          gateway: gatewayFactory(settings.moonclaw_gateway),
          beforeSubmit: async unsent => {
            // Historical health is sufficient only to observe/reconcile a prior
            // effect. A definite first submit must pass current native health.
            const fresh = await catalogSnapshot(root, handoff, settings, now());
            const refreshed = { ...unsent, evaluated_at: fresh.evaluated_at, recorded_at: fresh.evaluated_at };
            const key = sha(json(refreshed)).slice(7);
            const record = { request_id: task.request_id, catalog_ref: fresh.ref, catalog_digest: fresh.digest, evaluated_at: fresh.evaluated_at };
            // Immutable paired snapshots precede mutable pointers. Recovery can
            // resolve the matching catalog from the invocation digest if stopped
            // between those pointer writes and the dispatch journal checkpoint.
            await immutable(path.join(invocationSnapshots, `${key}.json`), refreshed);
            await immutable(path.join(catalogSnapshots, `${key}.json`), record);
            await atomicJson(invocationFile, refreshed);
            await atomicJson(invocationCatalogFile, record);
            await atomicJson(path.join(root, 'flow/capability-catalog.json'), fresh.catalog);
            return refreshed;
          },
          reconcileFlow: receiptPath => runMoonflow(settings.moonflow_binary, ['reconcile-attempt', root, id, receiptPath]),
        });
        return { ...await state(id), dispatch: result };
      }
      if (action === 'assemble') {
        const current = await projection(id), outputs = await reviewedOutputs(root, handoff, current);
        const sections = [`# ${handoff.source.outcome}`, '', `Scope: ${handoff.execution_digest}`, 'Internal reviewed task outputs. Customer acceptance, delivery and payment remain separate.', ''];
        const entries = [];
        for (const { task, artifacts } of outputs) {
          sections.push(`## ${task.name}`, `Owner: ${task.owner_name} (${task.owner_id})`, `Review: ${task.review_id} by ${task.reviewer_id}`, '');
          for (const artifact of artifacts) {
            sections.push(`Artifact: ${artifact.ref}`, `SHA-256: ${artifact.digest}`, '');
            if (/\.(md|txt|json|csv)$/i.test(artifact.ref)) sections.push(artifact.bytes.toString('utf8'), '');
            else sections.push('Binary artifact retained at its original reference.', '');
            entries.push({ task_id: task.task_id, artifact_ref: artifact.ref, digest: artifact.digest, result_id: task.result_id, review_id: task.review_id, output_digest: task.output_digest, receipt_ref: artifact.receipt_ref });
          }
        }
        for (const record of handoff.source.rework?.carried_artifacts || []) {
          const bytes = await bytesAt(root, record.artifact_ref);
          if (sha(bytes) !== record.digest) throw Error('Retained output changed');
          sections.push(`## Retained: ${record.name}`, `Owner: ${record.owner_name}`, `Original review: ${record.review_id}`, `Artifact: ${record.artifact_ref}`, '');
          if (/\.(md|txt|json|csv)$/i.test(record.artifact_ref)) sections.push(bytes.toString('utf8'), '');
          entries.push(record);
        }
        const content = sections.join('\n');
        const assembly = { contract_id: 'moonproj.deliverable-assembly.v1', execution_digest: handoff.execution_digest, content_digest: sha(content), entries, customer_accepted: false };
        await immutable(path.join(root, 'assembled.md'), content); await immutable(path.join(root, 'assembly.json'), assembly);
        return { ...await state(id), assembly, text: content };
      }
      if (['capacity', 'specialists', 'owner-handoff-preview', 'owner-handoff', 'prerequisites-preview', 'prerequisites', 'source-assignment-preview', 'source-assignment'].includes(action)) {
        // Even prepared but unsent work may have retained identities. Never
        // rescope an imported board or infer cancellation from a status label.
        if (action.startsWith('source-assignment') && await hasNativeState(root, id)) throw Error('Source assignment requires an unimported board with no pending native preparation; preserve and reconcile existing work');
        if (await projection(id)) throw Error('Delegation planning requires an unimported board; preserve and reconcile existing work');
        if (action.startsWith('prerequisites') && (await projection(id) !== null || await readJson(path.join(root, 'runtime/prepare-intent.json'), true) !== null)) throw Error('Prerequisite revision requires an unimported board with no pending native preparation; preserve and reconcile existing work');
        const sourcePlan = await bytesAt(root, 'source-plan.json');
        const child = action.startsWith('source-assignment') ? proposeEvidenceAssignment({ handoff, taskId: body.taskId, artifactRefs: body.artifactRefs, reason: body.reason, executionDigest: body.executionDigest, recordedAt: now() }) : action.startsWith('prerequisites') ? proposeDependencyRevision({ handoff, taskId: body.taskId, dependencies: body.dependencies, reason: body.reason, executionDigest: body.executionDigest, recordedAt: now() }) : action.startsWith('owner-handoff') ? proposeOwnerHandoff({ handoff, taskId: body.taskId, ownerId: body.ownerId, reason: body.reason, planText: sourcePlan.toString('utf8'), recordedAt: now() }) : action === 'capacity' ? proposeCapacity({ handoff, ownerLimits: body.ownerLimits, recordedAt: now() }) :
          proposeSpecialists({ handoff, taskId: body.taskId, specialists: body.specialists, recordedAt: now() });
        if (sha(sourcePlan) !== handoff.source.plan_digest) throw Error('Source plan bytes changed');
        if (action.startsWith('source-assignment')) {
          await evidenceBytes(root, handoff);
          if (action === 'source-assignment-preview') return { ...projectDeliverable(child, null), source: child.source, graph: child.graph, execution_digest: child.execution_digest, preview: true };
          if (body.previewDigest !== child.execution_digest) throw Error('Preview this exact source assignment before saving');
        }
        if (action.startsWith('prerequisites')) {
          await evidenceBytes(root, handoff);
          if (action === 'prerequisites-preview') return { ...projectDeliverable(child, null), source: child.source, graph: child.graph, execution_digest: child.execution_digest, preview: true };
          if (body.previewDigest !== child.execution_digest) throw Error('Preview this exact prerequisite revision before saving');
        }
        if (action === 'owner-handoff-preview') return { ...projectDeliverable(child, null), source: child.source, graph: child.graph, execution_digest: child.execution_digest, preview: true };
        if (action === 'owner-handoff' && body.previewDigest !== child.execution_digest) throw Error('Preview this exact owner handoff before saving');
        const childRoot = rootFor(child.id);
        await persistEvidence(childRoot, child, await evidenceBytes(root, handoff));
        await immutable(path.join(childRoot, 'source-plan.json'), sourcePlan);
        const existing = await readJson(path.join(childRoot, 'handoff.json'), true);
        if (existing) verifyDeliverable(existing);
        await persist(existing || child);
        return state(child.id);
      }
      if (action === 'rework') {
        const current = await projection(id);
        const child = proposeRework({ handoff, projection: current, taskId: body.taskId, reason: body.reason, recordedAt: now() });
        const retained = await reviewedOutputs(root, handoff, current, child.source.rework.retained.map(t => t.task_id).filter(id => handoff.source.tasks.some(t => t.task_id === id)));
        const records = [], carriedBytes = new Map();
        for (const record of handoff.source.rework?.carried_artifacts || []) {
          const bytes = await bytesAt(root, record.artifact_ref);
          if (sha(bytes) !== record.digest) throw Error('Retained output changed');
          records.push(record); carriedBytes.set(record.artifact_ref, bytes);
        }
        for (const output of retained) for (const [index, artifact] of output.artifacts.entries()) {
          const ref = `retained/${output.task.task_id}/${index}-${path.basename(artifact.ref)}`;
          carriedBytes.set(ref, artifact.bytes);
          records.push({ task_id: output.task.task_id, name: output.task.name, owner_name: output.task.owner_name, original_ref: artifact.ref, artifact_ref: ref, digest: artifact.digest, result_id: output.task.result_id, review_id: output.task.review_id });
        }
        // The manifest is a content-addressed carry-in; actual files must also be
        // declared inputs so native Flow binds their bytes into every attempt.
        // Rebuild through the public rework helper with the retained byte mapping.
        const final = withCarriedArtifacts(child, records);
        const finalRoot = rootFor(final.id);
        const sourcePlan = await bytesAt(root, 'source-plan.json');
        if (sha(sourcePlan) !== handoff.source.plan_digest) throw Error('Source plan bytes changed');
        await persistEvidence(finalRoot, final, await evidenceBytes(root, handoff));
        await immutable(path.join(finalRoot, 'source-plan.json'), sourcePlan);
        for (const record of records) await immutable(path.join(finalRoot, record.artifact_ref), carriedBytes.get(record.artifact_ref));
        await immutable(path.join(finalRoot, 'inputs/retained-outputs.json'), final.source.rework);
        const existing = await readJson(path.join(finalRoot, 'handoff.json'), true);
        if (existing) verifyDeliverable(existing);
        await persist(existing || final);
        return state(final.id);
      }
      throw Error('Unsupported deliverable action');
    } finally { busy.delete(id); }
  }
  return { list, state, act };
}
