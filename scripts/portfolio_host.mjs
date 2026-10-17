import http from 'node:http';
import { readFile, writeFile, mkdir, rename, access, lstat, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import { promisify } from 'node:util';
import { createDeliverableHost } from './deliverable_host.mjs';
import { createExecutionHandoff, createCapabilityInvocation, projectExecution, verifyPlanReview } from './portfolio_execution.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const dist = path.resolve(process.env.MOONPROJ_DIST || path.join(repo, 'dist/opc'));
const data = path.resolve(process.env.MOONPROJ_PORTFOLIO_DATA || path.join(os.homedir(), 'Library/Application Support/MoonProj/portfolio-workspace'));
const port = Number(process.env.MOONPROJ_PORT || 4310);
const catalog = JSON.parse(await readFile(path.join(repo, 'frontend/opc_public/portfolio_catalog.json'), 'utf8'));
if (catalog.schema !== 'moonproj.portfolio.catalog.v1' || catalog.products.length !== 26) throw Error('Invalid bundled portfolio catalog');
await mkdir(data, { recursive: true, mode: 0o700 });
const statePath = path.join(data, 'state.json');
let state;
try { state = JSON.parse(await readFile(statePath, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw error; state = { schema: 'moonproj.portfolio.runs.v1', jobs: {} }; }
if (state.schema !== 'moonproj.portfolio.runs.v1' || !state.jobs || typeof state.jobs !== 'object') throw Error('Invalid durable portfolio state; preserve and inspect the file');
for (const [key, job] of Object.entries(state.jobs)) {
  if (!job || typeof job !== 'object' || key !== job.id || key !== `${job.productId}:${job.requirementId}` || !/^[a-f0-9]{20}$/.test(job.runId) || !/^sha256:[a-f0-9]{64}$/.test(job.sourceDigest) || !['queued', 'running', 'interrupted', 'failed', 'cancelled', 'produced'].includes(job.status) || (job.artifactRef && (!/^\.moonsuite\/products\/moonproj\/adapter-attempts\/[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_./-]+\.json$/.test(job.artifactRef) || job.artifactRef.includes('..')))) throw Error(`Invalid durable job ${key}; preserve and inspect the file`);
}
for (const job of Object.values(state.jobs)) if (job.status === 'running') { job.status = 'interrupted'; job.message = 'Host restarted before an execution result was recorded; retry the same request to reconcile.'; }
let saveChain = Promise.resolve();
function save() {
  const snapshot = JSON.stringify(state, null, 2) + '\n';
  saveChain = saveChain.then(async () => { const temp = `${statePath}.${process.pid}.tmp`; await writeFile(temp, snapshot, { mode: 0o600 }); await rename(temp, statePath); });
  return saveChain;
}
await save();
const active = new Map();
const execFileAsync = promisify(execFile);
const executionConfigPath = process.env.MOONPROJ_EXECUTION_CONFIG || '';
const sha = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
const cleanTime = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const send = (res, status, body, type = 'application/json; charset=utf-8') => { const text = typeof body === 'string' ? body : JSON.stringify(body); res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(text); };
const keyFor = (product, req) => `${product}:${req}`;
async function readOperatorJson(file) {
  if (!path.isAbsolute(file) || await realpath(file) !== file) throw Error('Operator file must have a canonical absolute path');
  const stat = await lstat(file);
  if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) throw Error('Operator file must be owner-only and regular');
  return JSON.parse(await readFile(file, 'utf8'));
}
async function executionConfig() {
  if (!executionConfigPath) return null;
  const config = await readOperatorJson(executionConfigPath);
  if (config.contract_id !== 'moonproj.portfolio-execution-config.v1' || !path.isAbsolute(config.workspace_root || '') || !path.isAbsolute(config.review_file || '') || typeof config.model_selector !== 'string') throw Error('Invalid portfolio execution configuration');
  return config;
}
async function runMoonflow(binary, args) {
  if (!path.isAbsolute(binary) || await realpath(binary) !== binary) throw Error('MoonFlow binary must be a canonical absolute path');
  const stat = await lstat(binary);
  if (!stat.isFile() || (stat.mode & 0o111) === 0) throw Error('Configured MoonFlow binary is not executable');
  const { stdout } = await execFileAsync(binary, args, { cwd: repo, timeout: 30000, maxBuffer: 1_000_000 });
  return JSON.parse(stdout);
}
async function handoffFor(job) {
  const config = await executionConfig();
  if (!config) throw Error('Implementation handoff is not configured');
  const { row } = selected(job.productId, job.requirementId);
  const runRoot = path.join(data, 'runs', job.runId);
  const planText = await readFile(path.join(runRoot, job.artifactRef), 'utf8');
  const handoff = createExecutionHandoff({ job, planText, requirement: row, workspaceRoot: config.workspace_root, modelSelector: config.model_selector, recordedAt: job.updatedAt });
  const review = await readOperatorJson(config.review_file);
  const approval = verifyPlanReview({ review, handoff, job });
  return { handoff, approval, runRoot };
}
async function executionFor(job) {
  if (job.status !== 'produced') return null;
  const runRoot = path.join(data, 'runs', job.runId);
  const manifestPath = path.join(runRoot, 'runtime', 'execution-handoff.json');
  const exists = await access(manifestPath).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
  if (!exists) return { status: 'awaiting_approved_handoff', accepted: false };
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  const { handoff } = await handoffFor(job);
  if (manifest.contract_id !== 'moonproj.portfolio-execution-handoff.v1' || manifest.plan_digest !== handoff.planDigest || manifest.run_id !== handoff.identity.runId) throw Error('Stored handoff no longer matches the approved plan');
  const projectionPath = path.join(runRoot, '.moonsuite', 'products', 'moonflow', 'runs', handoff.identity.runId, 'projection.json');
  const projectionExists = await access(projectionPath).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
  if (!projectionExists) return { status: 'ready_for_moonflow', runId: handoff.identity.runId, sessionId: handoff.identity.sessionId, goalId: handoff.identity.goalId, accepted: false };
  const execution = projectExecution(handoff, JSON.parse(await readFile(projectionPath, 'utf8')));
  const invocationPath = path.join(runRoot, 'runtime', 'capability-invocation.json');
  const invocationExists = await access(invocationPath).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
  if (invocationExists) {
    const invocation = JSON.parse(await readFile(invocationPath, 'utf8'));
    if (invocation.request?.request_id !== execution.requestId) throw Error('Stored invocation does not match the MoonFlow attempt');
    execution.invocationPrepared = true;
    execution.providerCallsForbidden = invocation.config?.provider_calls_forbidden !== false;
  }
  return execution;
}
async function portfolioState() {
  const jobs = [];
  for (const job of Object.values(state.jobs).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))) {
    let implementation;
    try { implementation = await executionFor(job); }
    catch (error) { implementation = { status: 'verification_blocked', accepted: false, blocker: error.message }; }
    jobs.push({ ...job, implementation });
  }
  return { schema: state.schema, jobs, executionConfigured: Boolean(executionConfigPath), execution: executionConfigPath ? 'MoonFlow work handoff requires an exact named plan review; MoonClaw and MoonGate calls remain separately gated' : 'MoonClaw/MoonFlow handoff disconnected; MoonProj local plan adapter available by explicit click' };
}
function selected(productId, requirementId) {
  const product = catalog.products.find(item => item.id === productId && item.lifecycle === 'active');
  const row = product?.requirements.find(item => item['Requirement ID'] === requirementId);
  if (!product || !row) throw Error('Unknown active product or requirement');
  return { product, row };
}
function makeInputs(product, row, job) {
  const id = row['Requirement ID'];
  const now = cleanTime();
  const evidence = `Source assessment from the bundled OPC OS PRD. This is not fresh runtime verification.\nProduct: ${product.name}\nRequirement: ${id} ${row['Requirement title']}\nStatement: ${row['Requirement statement']}\nAcceptance: ${row['Acceptance criteria']}\nEvidence and sources: ${row['Evidence and sources']}\n`;
  const evidenceRef = 'inputs/requirement.txt';
  const requestRef = 'inputs/project-plan-request.json';
  const acceptance = row['Acceptance criteria'].trim();
  const request = {
    contract_id: 'moonproj.project-plan-request.v1', operation_ref: 'moonproj/project.plan.prepare@0.1.0',
    plan_request_id: `plan-${id.toLowerCase()}`, project: { project_id: `portfolio-${product.id}`, principal_id: 'local-founder-review', code: product.id.toUpperCase(), name: `${product.name} improvement` },
    prepared_by: 'founder-review', prepared_at: now,
    owners: [{ owner_id: 'founder-review', display_name: 'Accountable founder', role: 'plan-owner-and-reviewer' }],
    budget_envelope: { currency: 'USD', limit_minor: '0', contingency_minor: '0' },
    tasks: [{ task_id: `work-${id.toLowerCase()}`, name: row['Requirement title'], owner_id: 'founder-review', milestone_id: 'milestone-review', planned_cost_minor: '0', dependencies: [], acceptance_gate_ids: ['gate-founder-review'], source_evidence_refs: [evidenceRef] }],
    milestones: [{ milestone_id: 'milestone-review', name: 'Review produced work against requirement', owner_id: 'founder-review', target_date: now.slice(0, 10), task_ids: [`work-${id.toLowerCase()}`], acceptance_gate_ids: ['gate-founder-review'] }],
    risks: [{ risk_id: 'risk-source-status', summary: 'Imported source assessment is not fresh independent verification', severity: 'medium', owner_id: 'founder-review', mitigation: 'Review actual output and source freshness before acceptance', related_task_ids: [`work-${id.toLowerCase()}`], source_evidence_refs: [evidenceRef] }],
    acceptance_gates: [{ gate_id: 'gate-founder-review', name: 'Founder accepts result', owner_id: 'founder-review', scope_type: 'milestone', scope_id: 'milestone-review', criteria: [acceptance], required_evidence: ['Produced artifact and named founder review'] }],
    source_evidence: [{ artifact_ref: evidenceRef, digest: sha(evidence), observed_at: now, kind: 'prd-source-assessment-unverified' }],
  };
  const requestText = JSON.stringify(request, null, 2) + '\n';
  const artifacts = [requestRef, evidenceRef];
  const digest = sha(artifacts.map(ref => `${ref}|${sha(ref === requestRef ? requestText : evidence)}`).join('\n'));
  const attempt = `portfolio-${product.id}-${id.toLowerCase()}`;
  const flow = {
    request_id: `request-${attempt}`, run_id: `portfolio-${product.id}`, book_id: 'moonproj-portfolio', work_item_id: `work-${id.toLowerCase()}`, declaration_id: `plan-${id.toLowerCase()}`,
    attempt_id: attempt, idempotency_key: `${product.id}/${id}/${job.sourceDigest}`, product_id: 'moonproj', operation: 'moonproj/project.plan.prepare@0.1.0',
    requested_authority: 'workspace-mutation', acceptance_criteria: [acceptance], input_contracts: ['moonproj/project-plan-request@1.0.0'], output_contracts: ['moonproj/project-plan-artifact@1.0.0'], required_claim: 'digital-artifact', input_digest: digest, input_artifacts: artifacts, timeout_ms: 120000, created_at: now,
  };
  return { evidence, requestText, flow };
}
async function start(job, retry = false) {
  const { product, row } = selected(job.productId, job.requirementId);
  const work = path.join(data, 'runs', job.runId);
  await mkdir(path.join(work, 'inputs'), { recursive: true, mode: 0o700 });
  await mkdir(path.join(work, 'runtime'), { recursive: true, mode: 0o700 });
  const { evidence, requestText, flow } = makeInputs(product, row, job);
  // A retry uses immutable original inputs. The existing adapter reconciles its own attempt.
  if (!retry) {
    await writeFile(path.join(work, 'inputs/requirement.txt'), evidence, { flag: 'wx', mode: 0o600 });
    await writeFile(path.join(work, 'inputs/project-plan-request.json'), requestText, { flag: 'wx', mode: 0o600 });
    await writeFile(path.join(work, 'runtime/request.json'), JSON.stringify(flow, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  }
  job.status = 'running'; job.message = 'MoonProj project.plan.prepare is running locally'; job.updatedAt = cleanTime(); await save();
  const intent = path.join(work, '.moonsuite', 'products', 'moonproj', 'adapter-attempts', flow.attempt_id, 'intent.json');
  const hasIntent = retry && await access(intent).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
  const args = ['run', '--strip', '--target', 'native', '-j', '2', 'cmd/moonflow_project_plan_adapter', hasIntent ? 'reconcile' : 'execute', '--workspace', work, '--request', 'runtime/request.json', '--result', 'runtime/result.json'];
  const child = spawn('moon', args, { cwd: repo, stdio: ['ignore', 'pipe', 'pipe'], detached: true });
  active.set(job.id, child);
  let output = '';
  for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => { output = (output + chunk.toString()).slice(-12000); });
  child.on('error', async error => { active.delete(job.id); job.status = 'failed'; job.message = error.message; job.updatedAt = cleanTime(); await save(); });
  child.on('close', async code => {
    active.delete(job.id);
    if (job.status === 'cancelled' || job.status === 'interrupted') return;
    try {
      if (code !== 0) throw Error(`Adapter exit ${code}: ${output.slice(-500)}`);
      const result = JSON.parse(await readFile(path.join(work, 'runtime/result.json'), 'utf8'));
      if (result.status !== 'succeeded' || !Array.isArray(result.output_artifacts) || result.output_artifacts.length !== 1) throw Error('Adapter returned no successful artifact receipt');
      const rel = result.output_artifacts[0];
      if (!/^\.moonsuite\/products\/moonproj\/adapter-attempts\/[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_./-]+\.json$/.test(rel) || rel.includes('..')) throw Error('Unsafe artifact reference');
      const artifact = JSON.parse(await readFile(path.join(work, rel), 'utf8'));
      if (artifact.contract_id !== 'moonproj.project-plan-artifact.v1' || artifact.workflow?.status !== 'pending_review') throw Error('Unexpected plan artifact');
      job.status = 'produced'; job.artifactRef = rel; job.message = 'Review-pending project plan artifact produced by MoonProj adapter; implementation work is still pending.';
    } catch (error) { job.status = 'failed'; job.message = error.message; }
    job.updatedAt = cleanTime(); await save();
  });
}
const deliverables = createDeliverableHost({ data, config: executionConfig, readOperatorJson, runMoonflow });
function readBody(req, limit = 10000) { return new Promise((resolve, reject) => { let raw = ''; req.on('data', chunk => { raw += chunk; if (raw.length > limit) { reject(Error('Body too large')); req.destroy(); } }); req.on('end', () => { try { resolve(JSON.parse(raw)); } catch { reject(Error('Invalid JSON')); } }); req.on('error', reject); }); }
const server = http.createServer(async (req, res) => {
  try {
    const host = req.headers.host || '';
    if (![ `127.0.0.1:${port}`, `localhost:${port}` ].includes(host)) return send(res, 403, { error: 'Loopback host required' });
    if (req.method !== 'GET' && req.headers.origin && ![`http://127.0.0.1:${port}`, `http://localhost:${port}`].includes(req.headers.origin)) return send(res, 403, { error: 'Cross-origin write denied' });
    const url = new URL(req.url, `http://${host}`);
    if (url.pathname === '/api/deliverables' && req.method === 'GET') return send(res, 200, { deliverables: await deliverables.list() });
    if (/^\/api\/deliverables\/(create|preview|inspect-evidence|delegation-brief|prepare|dispatch|assemble|rework|capacity|specialists|owner-handoff-preview|owner-handoff|prerequisites-preview|prerequisites|source-assignment-preview|source-assignment)$/.test(url.pathname) && req.method === 'POST') {
      const body = await readBody(req, 1000000);
      return send(res, 200, await deliverables.act(url.pathname.split('/').at(-1), body));
    }
    if (url.pathname === '/api/portfolio/state' && req.method === 'GET') return send(res, 200, await portfolioState());
    if (url.pathname === '/api/portfolio/handoff' && req.method === 'POST') {
      const body = await readBody(req);
      if (Object.keys(body).join(',') !== 'id' || typeof body.id !== 'string') return send(res, 400, { error: 'Expected an exact job id' });
      const job = state.jobs[body.id];
      if (!job || job.status !== 'produced') return send(res, 409, { error: 'A produced plan is required' });
      const { handoff, approval, runRoot } = await handoffFor(job);
      const files = [
        ['inputs/agent-goal-execution-request.json', handoff.request],
        ['flow/work-graph.json', handoff.graph],
        ['runtime/execution-handoff.json', { contract_id: 'moonproj.portfolio-execution-handoff.v1', run_id: handoff.identity.runId, plan_digest: handoff.planDigest, source_digest: job.sourceDigest, approval, session_id: handoff.identity.sessionId, goal_id: handoff.identity.goalId, status: 'ready_for_moonflow' }],
      ];
      for (const [ref, value] of files) {
        const target = path.join(runRoot, ref);
        await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
        const text = JSON.stringify(value, null, 2) + '\n';
        try { await writeFile(target, text, { flag: 'wx', mode: 0o600 }); }
        catch (error) { if (error.code !== 'EEXIST' || await readFile(target, 'utf8') !== text) throw Error('Existing handoff differs; reconcile exact plan before retry'); }
      }
      return send(res, 200, { status: 'ready_for_moonflow', runId: handoff.identity.runId, sessionId: handoff.identity.sessionId, goalId: handoff.identity.goalId, graphRef: 'flow/work-graph.json', requestRef: 'inputs/agent-goal-execution-request.json', providerCalls: 'forbidden until separately approved' });
    }
    if (url.pathname.startsWith('/api/portfolio/handoff/') && req.method === 'GET') {
      const id = decodeURIComponent(url.pathname.slice('/api/portfolio/handoff/'.length));
      const job = state.jobs[id];
      if (!job || job.status !== 'produced') return send(res, 404, { error: 'No produced plan' });
      const manifest = path.join(data, 'runs', job.runId, 'runtime', 'execution-handoff.json');
      return send(res, 200, await readFile(manifest, 'utf8'), 'application/json; charset=utf-8');
    }
    if (url.pathname === '/api/portfolio/flow' && req.method === 'POST') {
      const body = await readBody(req);
      if (Object.keys(body).join(',') !== 'id' || typeof body.id !== 'string') return send(res, 400, { error: 'Expected an exact job id' });
      const job = state.jobs[body.id];
      if (!job || job.status !== 'produced') return send(res, 409, { error: 'A produced plan is required' });
      const { handoff, runRoot } = await handoffFor(job);
      const manifest = JSON.parse(await readFile(path.join(runRoot, 'runtime', 'execution-handoff.json'), 'utf8'));
      if (manifest.plan_digest !== handoff.planDigest || manifest.run_id !== handoff.identity.runId) throw Error('Approved handoff changed');
      const config = await executionConfig();
      if (!path.isAbsolute(config.moonflow_binary || '') || !path.isAbsolute(config.catalog_file || '')) throw Error('MoonFlow binary and catalog are not configured');
      if (await realpath(config.catalog_file) !== config.catalog_file) throw Error('MoonFlow catalog path must be canonical');
      const catalogStat = await lstat(config.catalog_file);
      if (!catalogStat.isFile() || catalogStat.size > 1_000_000) throw Error('MoonFlow catalog is unavailable or too large');
      const catalogText = await readFile(config.catalog_file, 'utf8');
      const catalogTarget = path.join(runRoot, 'flow', 'capability-catalog.json');
      try { await writeFile(catalogTarget, catalogText, { flag: 'wx', mode: 0o600 }); }
      catch (error) { if (error.code !== 'EEXIST' || await readFile(catalogTarget, 'utf8') !== catalogText) throw Error('Capability catalog changed during this run'); }
      const projectionPath = path.join(runRoot, '.moonsuite', 'products', 'moonflow', 'runs', handoff.identity.runId, 'projection.json');
      const imported = await access(projectionPath).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
      if (!imported) await runMoonflow(config.moonflow_binary, ['import-conformant-graph', runRoot, path.join(runRoot, 'flow', 'work-graph.json'), catalogTarget, cleanTime()]);
      const before = projectExecution(handoff, JSON.parse(await readFile(projectionPath, 'utf8')));
      if (!before.requestId) await runMoonflow(config.moonflow_binary, ['prepare-next', runRoot, handoff.identity.runId, 'flow/capability-catalog.json', cleanTime()]);
      const execution = projectExecution(handoff, JSON.parse(await readFile(projectionPath, 'utf8')));
      return send(res, 200, { status: execution.status, runId: execution.runId, requestId: execution.requestId, attemptId: execution.attemptId, providerCalls: 'not invoked' });
    }
    if (url.pathname === '/api/portfolio/invocation' && req.method === 'POST') {
      const body = await readBody(req);
      if (Object.keys(body).join(',') !== 'id' || typeof body.id !== 'string') return send(res, 400, { error: 'Expected an exact job id' });
      const job = state.jobs[body.id];
      if (!job || job.status !== 'produced') return send(res, 409, { error: 'A produced plan is required' });
      const { handoff, runRoot } = await handoffFor(job);
      const projection = JSON.parse(await readFile(path.join(runRoot, '.moonsuite', 'products', 'moonflow', 'runs', handoff.identity.runId, 'projection.json'), 'utf8'));
      const correlated = projectExecution(handoff, projection);
      if (!correlated.requestId || !/^[A-Za-z0-9._-]{1,128}$/.test(correlated.requestId)) return send(res, 409, { error: 'MoonFlow has not prepared an exact attempt' });
      const preparedRequest = JSON.parse(await readFile(path.join(runRoot, '.moonsuite', 'products', 'moonflow', 'runs', handoff.identity.runId, 'dispatch', `${correlated.requestId}.request.json`), 'utf8'));
      const config = await executionConfig();
      const target = path.join(runRoot, 'runtime', 'capability-invocation.json');
      const existing = await access(target).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
      if (existing) {
        const invocation = JSON.parse(await readFile(target, 'utf8'));
        if (invocation.request?.request_id !== correlated.requestId || invocation.request?.idempotency_key !== preparedRequest.idempotency_key) throw Error('Existing invocation belongs to another attempt');
        return send(res, 200, { status: 'prepared', invocationRef: 'runtime/capability-invocation.json', providerCallsForbidden: invocation.config?.provider_calls_forbidden !== false, duplicate: true });
      }
      const invocation = createCapabilityInvocation({ handoff, preparedRequest, adapterId: 'moonclaw-agent-goal-v1', recordedAt: cleanTime(), allowProviderCalls: config.provider_calls_approved === true });
      await writeFile(target, JSON.stringify(invocation, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
      return send(res, 200, { status: 'prepared', invocationRef: 'runtime/capability-invocation.json', providerCallsForbidden: invocation.config.provider_calls_forbidden, duplicate: false });
    }
    if (url.pathname.startsWith('/api/portfolio/invocation/') && req.method === 'GET') {
      const id = decodeURIComponent(url.pathname.slice('/api/portfolio/invocation/'.length));
      const job = state.jobs[id];
      if (!job || job.status !== 'produced') return send(res, 404, { error: 'No produced plan' });
      return send(res, 200, await readFile(path.join(data, 'runs', job.runId, 'runtime', 'capability-invocation.json'), 'utf8'), 'application/json; charset=utf-8');
    }
    if (url.pathname === '/api/portfolio/plan' && req.method === 'POST') {
      const body = await readBody(req);
      if (Object.keys(body).sort().join(',') !== 'productId,requirementId') return send(res, 400, { error: 'Expected productId and requirementId only' });
      const { product, row } = selected(body.productId, body.requirementId);
      const sourceDigest = sha(JSON.stringify(row)); const key = keyFor(product.id, row['Requirement ID']);
      let job = state.jobs[key];
      if (job && job.sourceDigest !== sourceDigest) return send(res, 409, { error: 'Requirement changed; existing run is retained. Explicit version reconciliation is needed.' });
      if (job && !['queued', 'failed', 'cancelled', 'interrupted'].includes(job.status)) return send(res, 200, { job, duplicate: true });
      if (active.size) return send(res, 409, { error: 'Another local adapter run is active; wait or cancel it before starting a second build.' });
      const retry = Boolean(job);
      if (!job) { const runId = createHash('sha256').update(key + sourceDigest).digest('hex').slice(0, 20); job = { id: key, productId: product.id, requirementId: row['Requirement ID'], sourceDigest, runId, status: 'queued', artifactRef: '', message: '', updatedAt: cleanTime() }; state.jobs[key] = job; await save(); }
      if (active.has(job.id)) return send(res, 200, { job, duplicate: true });
      await start(job, retry);
      return send(res, 202, { job, duplicate: false });
    }
    if (url.pathname === '/api/portfolio/cancel' && req.method === 'POST') {
      const body = await readBody(req); const job = state.jobs[body.id]; const child = active.get(body.id);
      if (!job || !child) return send(res, 409, { error: 'No running job with this ID' });
      job.status = 'cancelled'; job.message = 'Local adapter process cancelled. Retry resumes the same attempt, reconciling durable intent when present.'; job.updatedAt = cleanTime(); await save();
      try { process.kill(-child.pid, 'SIGTERM'); } catch { child.kill('SIGTERM'); }
      return send(res, 200, { job });
    }
    if (url.pathname.startsWith('/api/portfolio/artifact/') && req.method === 'GET') {
      const id = decodeURIComponent(url.pathname.slice('/api/portfolio/artifact/'.length)); const job = state.jobs[id];
      if (!job || job.status !== 'produced' || !job.artifactRef) return send(res, 404, { error: 'No produced artifact' });
      const target = path.join(data, 'runs', job.runId, job.artifactRef);
      return send(res, 200, await readFile(target, 'utf8'), 'application/json; charset=utf-8');
    }
    if (req.method !== 'GET') return send(res, 405, { error: 'Unsupported method' });
    let pathname = decodeURIComponent(url.pathname);
    if (pathname === '/') pathname = '/index.html';
    if (!/^\/[A-Za-z0-9_./-]+$/.test(pathname) || pathname.includes('..')) return send(res, 400, { error: 'Invalid static path' });
    const target = path.join(dist, pathname);
    const type = pathname.endsWith('.js') ? 'text/javascript; charset=utf-8' : pathname.endsWith('.css') ? 'text/css; charset=utf-8' : pathname.endsWith('.json') ? 'application/json; charset=utf-8' : pathname.endsWith('.svg') ? 'image/svg+xml' : 'text/html; charset=utf-8';
    return send(res, 200, await readFile(target, 'utf8'), type);
  } catch (error) { return send(res, error.code === 'ENOENT' ? 404 : 400, { error: error.message }); }
});
server.listen(port, '127.0.0.1', () => console.log(`MoonProj portfolio: http://127.0.0.1:${port}/ (data: ${data})`));
async function shutdown() {
  for (const [id, child] of active) {
    const job = state.jobs[id]; job.status = 'interrupted'; job.message = 'Local host stopped before completion; retry resumes the same adapter attempt.'; job.updatedAt = cleanTime();
    try { process.kill(-child.pid, 'SIGTERM'); } catch { child.kill('SIGTERM'); }
  }
  await save(); server.close();
}
process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);
