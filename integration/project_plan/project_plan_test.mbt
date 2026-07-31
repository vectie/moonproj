///|
fn digest(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn valid_request() -> @project_plan.ProjectPlanRequest {
  {
    contract_id: "moonproj.project-plan-request.v1",
    operation_ref: @project_plan.operation_ref(),
    plan_request_id: "plan-robotics-001",
    project: {
      project_id: "robotics-001",
      principal_id: "opc-001",
      code: "ROBOTICS-001",
      name: "Governed robotics delivery",
    },
    prepared_by: "owner-architect",
    prepared_at: "2026-07-31T00:00:00Z",
    owners: [
      {
        owner_id: "owner-architect",
        display_name: "Project Architect",
        role: "plan-owner",
      },
      {
        owner_id: "owner-reviewer",
        display_name: "Acceptance Reviewer",
        role: "independent-reviewer",
      },
    ],
    budget_envelope: {
      currency: "CNY",
      limit_minor: 1000000L,
      contingency_minor: 100000L,
    },
    tasks: [
      {
        task_id: "task-design",
        name: "Freeze the digital design",
        owner_id: "owner-architect",
        milestone_id: "milestone-design",
        planned_cost_minor: 200000L,
        dependencies: [],
        acceptance_gate_ids: ["gate-design"],
        source_evidence_refs: ["evidence/requirements.json"],
      },
      {
        task_id: "task-simulate",
        name: "Run the bounded simulation",
        owner_id: "owner-architect",
        milestone_id: "milestone-simulation",
        planned_cost_minor: 300000L,
        dependencies: ["task-design"],
        acceptance_gate_ids: ["gate-simulation"],
        source_evidence_refs: ["evidence/requirements.json"],
      },
    ],
    milestones: [
      {
        milestone_id: "milestone-design",
        name: "Design ready for review",
        owner_id: "owner-architect",
        target_date: "2026-08-15",
        task_ids: ["task-design"],
        acceptance_gate_ids: ["gate-design"],
      },
      {
        milestone_id: "milestone-simulation",
        name: "Simulation evidence ready",
        owner_id: "owner-architect",
        target_date: "2026-08-31",
        task_ids: ["task-simulate"],
        acceptance_gate_ids: ["gate-simulation"],
      },
    ],
    risks: [
      {
        risk_id: "risk-evidence",
        summary: "Input requirements may be incomplete",
        severity: "high",
        owner_id: "owner-reviewer",
        mitigation: "Hold the design gate until contradictory evidence is resolved",
        related_task_ids: ["task-design"],
        source_evidence_refs: ["evidence/requirements.json"],
      },
    ],
    acceptance_gates: [
      {
        gate_id: "gate-design",
        name: "Design acceptance",
        owner_id: "owner-reviewer",
        scope_type: "milestone",
        scope_id: "milestone-design",
        criteria: ["requirements are traceable"],
        required_evidence: ["named-human design receipt"],
      },
      {
        gate_id: "gate-simulation",
        name: "Simulation acceptance",
        owner_id: "owner-reviewer",
        scope_type: "milestone",
        scope_id: "milestone-simulation",
        criteria: ["simulation limits are explicit"],
        required_evidence: ["reviewed simulation receipt"],
      },
    ],
    source_evidence: [
      {
        artifact_ref: "evidence/requirements.json",
        digest: digest("a"),
        observed_at: "2026-07-31T00:00:00Z",
        kind: "accepted-requirements",
      },
    ],
  }
}

///|
test "project plan preparation reuses domain dependencies and remains pending review" {
  let artifact = @project_plan.prepare(
    valid_request(),
    "attempt-plan-1",
    digest("b"),
    "2026-07-31T00:05:00Z",
  )
  assert_eq(artifact.tasks.length(), 2)
  assert_eq(artifact.tasks[1].dependencies, ["task-design"])
  assert_eq(artifact.budget.planned_total_minor, 500000L)
  assert_eq(artifact.budget.unallocated_minor, 400000L)
  assert_eq(artifact.workflow.status, "pending_review")
  assert_true(artifact.workflow.review_required)
  assert_true(!artifact.workflow.accepted)
  assert_true(!artifact.authority_effects.spend_authorized)
  assert_true(!artifact.authority_effects.accounting_posted)
  assert_true(!artifact.authority_effects.work_executed)
}

///|
test "project plan rejects dependency order that the domain plan cannot satisfy" {
  let request = valid_request()
  let tasks = request.tasks.copy()
  tasks[0] = { ..tasks[0], dependencies: ["task-simulate"] }
  try
    @project_plan.prepare(
      { ..request, tasks, },
      "attempt-plan-invalid",
      digest("c"),
      "2026-07-31T00:05:00Z",
    )
  catch {
    @project_plan.ProjectPlanCapabilityError::Plan(
      @project.PlanError::MissingDependency
    ) => ()
    _ => fail("expected the ProjectPlan dependency invariant")
  } noraise {
    _ => fail("expected dependency rejection")
  }
}

///|
test "project plan rejects budget overrun before producing an artifact" {
  let request = valid_request()
  try
    @project_plan.prepare(
      {
        ..request,
        budget_envelope: {
          currency: "CNY",
          limit_minor: 400000L,
          contingency_minor: 0L,
        },
      },
      "attempt-plan-budget",
      digest("d"),
      "2026-07-31T00:05:00Z",
    )
  catch {
    @project_plan.ProjectPlanCapabilityError::Invalid(_) => ()
    _ => fail("expected a planning budget rejection")
  } noraise {
    _ => fail("expected budget rejection")
  }
}
