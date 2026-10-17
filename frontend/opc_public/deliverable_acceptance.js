// Shared execution-subset inspection. It does not approve or execute the plan.
const nonblank = value => typeof value === 'string' && value.trim() && value.length <= 4096;
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9._-]{1,80}$/.test(value) && !value.includes('..') && value !== '.';
const unique = values => new Set(values).size === values.length;
export function inspectAcceptancePlan(planText) {
  const plan = JSON.parse(planText);
  if (plan.contract_id !== 'moonproj.project-plan-artifact.v1' || plan.workflow?.status !== 'pending_review' ||
      plan.workflow.accepted !== false || !nonblank(plan.project?.project_id) ||
      !Array.isArray(plan.tasks) || !plan.tasks.length || plan.tasks.length > 100 ||
      !Array.isArray(plan.owners) || !Array.isArray(plan.acceptance_gates) ||
      !plan.authority_effects || ['spend_authorized', 'accounting_posted', 'payment_released', 'contract_signed', 'work_executed'].some(key => plan.authority_effects[key] !== false)) throw Error('A native review-pending plan and an explicit outcome are required');
  if (!unique(plan.tasks.map(t => t.task_id)) || !unique(plan.owners.map(o => o.owner_id)) || !unique(plan.acceptance_gates.map(g => g.gate_id))) throw Error('Duplicate plan task, owner or gate');
  const tasks = plan.tasks.map(task => {
    const owner = plan.owners.find(o => o.owner_id === task.owner_id);
    if (!identifier(task.task_id) || task.task_id.length > 80 || !nonblank(task.name) || !owner || !nonblank(owner.display_name) ||
        !Array.isArray(task.dependencies) || !unique(task.dependencies) ||
        task.dependencies.some(id => id === task.task_id || !plan.tasks.some(t => t.task_id === id)) ||
        !Array.isArray(task.acceptance_gate_ids) || !task.acceptance_gate_ids.length) throw Error(`Invalid owner or dependencies for ${task.task_id}`);
    const gates = task.acceptance_gate_ids.map(id => plan.acceptance_gates.find(g => g.gate_id === id));
    if (gates.some(g => !g || !Array.isArray(g.criteria) || !g.criteria.length || !g.criteria.every(nonblank) ||
      !Array.isArray(g.required_evidence) || !g.required_evidence.length || !g.required_evidence.every(nonblank) ||
      !(g.scope_type === 'task' && g.scope_id === task.task_id || g.scope_type === 'milestone' && g.scope_id === task.milestone_id || g.scope_type === 'project' && g.scope_id === plan.project.project_id))) throw Error(`Unresolved acceptance for ${task.task_id}`);
    return { ...task, owner_name: owner.display_name, gates };
  });
  const visiting = new Set(), visited = new Set();
  function visit(id) {
    if (visiting.has(id)) throw Error('Plan dependency cycle');
    if (visited.has(id)) return;
    visiting.add(id); tasks.find(t => t.task_id === id).dependencies.forEach(visit); visiting.delete(id); visited.add(id);
  }
  tasks.forEach(t => visit(t.task_id));
  return { plan, tasks };
}

export function acceptanceRows(planText) {
  return inspectAcceptancePlan(planText).tasks.map(task => {
    const inherited = task.gates.some(gate => gate.scope_type !== 'task');
    return { ...task, inherited,
      criteria: inherited ? '' : [...new Set(task.gates.flatMap(gate => gate.criteria))].join('\n'),
      evidence: inherited ? '' : [...new Set(task.gates.flatMap(gate => gate.required_evidence))].join('\n') };
  });
}
export function acceptanceMap(rows) {
  if (!Array.isArray(rows) || !rows.length || !unique(rows.map(row => row.task_id))) throw Error('Load a native plan before entering task acceptance');
  const lines = value => typeof value === 'string' ? value.split('\n').map(line => line.trim()).filter(Boolean) : [];
  return Object.fromEntries(rows.map(row => {
    const native = row.inherited ? null : { criteria: [...new Set(row.gates.flatMap(gate => gate.criteria))], evidence: [...new Set(row.gates.flatMap(gate => gate.required_evidence))] };
    const criteria = native && row.criteria === native.criteria.join('\n') ? native.criteria : lines(row.criteria);
    const required_evidence = native && row.evidence === native.evidence.join('\n') ? native.evidence : lines(row.evidence);
    if (!criteria.length || !required_evidence.length || !criteria.every(nonblank) || !required_evidence.every(nonblank)) throw Error(`Task ${row.task_id} needs explicit acceptance criteria and required evidence, one per line (up to 4096 characters per line)`);
    return [row.task_id, { criteria, required_evidence }];
  }));
}
export async function readNativePlanFile(file) {
  if (!file || !/\.json$/i.test(file.name) || !file.size || file.size > 1048576) throw Error('Choose one nonempty native plan JSON file up to 1 MiB');
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.length !== file.size) throw Error('Selected plan changed while reading; choose it again');
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { throw Error('Native plan must contain valid UTF-8 JSON'); }
  // The native JSON parser does not accept a BOM. Do not silently change source bytes.
  if (bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191) throw Error('Save the native plan as UTF-8 JSON without a byte-order mark');
  acceptanceRows(text);
  return text;
}
