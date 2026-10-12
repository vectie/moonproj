# Company task reports from the existing Flow plan adapter

For explicitly approved revised tasks and authenticated saved-report return, see
[Revised tasks](FLOW_REVISED_TASKS.md). The v1/manual compatibility path below is
unchanged; it does not implicitly inherit approval for revisions.

The existing project-plan adapter can now correlate a scoped company task with
its exact plan attempt and prepare a report for that task. This is an opt-in
producer bridge. MoonFlow remains domain-neutral. No scheduler, model loop,
HTTP listener, provider, reviewer policy, or automatic company acceptance is
added. Existing `execute`, `reconcile`, manifests and dependency versions are
unchanged.

## Bind one existing task

Obtain the persisted create `company_command` through the existing authenticated
MoonProj gateway. Retain its exact JSON bytes as a workspace-relative input file.
The supported initial slice is one create command at revision 1. Updates and
continuations require a separately declared future integration; the bridge does
not silently treat a newer task as its original approved snapshot.

Include that file in the existing adapter request's ordered `input_artifacts`,
and in the `moonproj.project-plan-request.v1` source-evidence list with its actual
SHA-256. Recompute the existing declared input digest, which hashes ordered
`reference|sha256:digest` lines. The plan project must match the company task's
project. The existing plan request still supplies the owner, tasks, budget,
milestones and acceptance gates; this bridge invents none of them.

Before invoking the existing adapter, call:

```text
moon run --target native cmd/moonflow_project_plan_adapter bind-company-task \
  --workspace WORKSPACE --request runtime/request.json
```

This writes an immutable `company-task-binding.json` beside the existing
adapter-attempt intent and output. It names the company task/project,
create-command event and audit references, Flow run/work/declaration/request/
attempt IDs, and the exact source and input digests. It grants no authority and
does not execute. Authentication remains at the existing gateway; an arbitrary
JSON file is not proof that its alleged signer was authenticated.

Invoke the existing `execute` or `reconcile` command normally. The plan artifact
retains the company snapshot as source evidence. Source reference/problem text
is preserved within the exact command input. An external document named by a
source reference is not fetched by this feature.

## Prepare and return a report

After the exact adapter result exists, prepare one stable report:

```text
moon run --target native cmd/moonflow_project_plan_adapter prepare-company-report \
  --workspace WORKSPACE --request runtime/request.json --result runtime/result.json \
  --report-key plan-output --date 2026-10-04 --summary 'Prepared the scoped plan' \
  --evidence flow-review.json --evidence claw-named-output.json
```

Additional evidence is optional. Exact output names, result references and
SHA-256 values are retained in the report envelope; the existing company report
body receives compatible content-digest evidence IDs. For example, a Claw
ArtifactStore record and a Flow acceptance-review receipt travel as evidence
files without either repository becoming a source dependency of MoonProj.
The bridge does not reinterpret a review as company/customer acceptance.

The result contains `method`, `path`, `idempotency_key` and `report_body`.
Submit that saved body explicitly through the existing authenticated gateway:
`POST /api/company/plan/tasks/<task-id>/report`, using the saved `Idempotency-Key`.
The CLI performs no HTTP submission. The default report progress is zero;
the public API supports explicitly supplied whole-percent progress. A prepared
plan is not a claim that the plan's work has been executed. The existing service
still checks the actor, task and any selected native delivery source. A task
requiring native selected-source reporting needs that existing native flow;
this bridge does not bypass its requirements.

Save the service response as a workspace file and retain its exact command:

```text
moon run --target native cmd/moonflow_project_plan_adapter record-company-report \
  --workspace WORKSPACE --request runtime/request.json --report-key plan-output \
  --response company-report-response.json
moon run --target native cmd/moonflow_project_plan_adapter company-report-status \
  --workspace WORKSPACE --request runtime/request.json --report-key plan-output
```

The response must match the prepared report, idempotency key, task/project,
summary, progress, evidence IDs and observed command result. A repeated HTTP
response may change its outer `idempotent_replay` flag or JSON field order; the
persisted command identity stays the same. A conflicting command is refused.
Status distinguishes `pending_report`/`submit_saved_report` from
`reported`/`inspect_report`. It always leaves company task acceptance unchanged.

Recovery reconstructs the saved v1 report envelope against its original company
binding, request, attempt and report key. It rereads the persisted adapter result
and exact evidence bytes. Malformed, misbound or stale checkpoints fail before
returning an actionable status or writing a receipt. An observed report receipt
must include the existing service's complete command/result shape and revision
1; missing fields do not count as successful reporting.

If the gateway response is lost, resend the same report body and key, then retain
the returned command. Reporting retries do not call the adapter. A different
report draft uses a different report key; a changed body under an existing key
conflicts. Restarting reads the same immutable report and receipt files.

## Public API example

```mbt nocheck
let binding = @moonflow_adapter.bind_company_task(workspace, request_ref)
let result = @moonflow_adapter.execute(workspace, request_ref, result_ref)
let report = @moonflow_adapter.prepare_company_task_report(
  workspace, request_ref, result_ref, "plan-output", "2026-10-04",
  "Prepared the scoped plan", ["flow-review.json", "claw-named-output.json"],
)
// The caller explicitly submits report.report_body via the existing gateway.
let status = @moonflow_adapter.record_company_task_report_receipt(
  workspace, request_ref, "plan-output", "company-report-response.json",
)
```

The four new public APIs and CLI commands are exercised by isolated serialized
fixtures using real Flow event/replay/review functions, real Claw ArtifactStore,
and the actual company report route/normalizer. Company database persistence and
gateway authentication are separate qualification boundaries. Passing these
fixtures is not a live adapter, PostgreSQL restart, customer delivery, or cash
acceptance claim.
