# Explicit revised-task approval and exact report return

This is a bounded digital-plan workflow through MoonProj's existing authenticated
gateway and signed company service. MoonFlow remains domain-neutral and advances
only declared work. There is no new listener, scheduler, provider, spending,
customer acceptance, or cash transition.

The original create-command/revision-1 bridge in `FLOW_COMPANY_REPORTS.md` stays
compatible. The revised workflow uses `moonproj.company-task-snapshot.v1`,
`moonproj.flow-task-binding.v2`, and a separately persisted
`company_command/flow_task_binding/approve`. A snapshot or local receipt file by
itself is not proof of authentication. The normal path below obtains and returns
these records through the existing gateway session and service actor signature.

## Owner workflow

Use the configured existing gateway and its existing session. Pass the session
only through a process environment variable. The CLI never prints or saves it.
The gateway workspace is the configured `--moonsuite-workspace-root/moonproj`;
all request and evidence references below are relative to that same workspace.

1. Capture the current task revision:

   ```text
   moon run --target native cmd/moonflow_project_plan_adapter gateway-snapshot \
     --gateway http://127.0.0.1:PORT --session-env EXISTING_MOONPROJ_SESSION \
     --task PT-example > inputs/company-task-r2.json
   ```

   Only an active, local, owner-controlled task without native execution or a
   selected native delivery source is supported. Native continuation/reporting
   continues through its existing flow. Accepted, deleted, imported, or foreign
   tasks are refused. The snapshot preserves current task content and revision.

2. Prepare a new explicit Flow request and project-plan request using the existing
   adapter schema. Include the saved snapshot in ordered `input_artifacts` and
   `source_evidence`, with its actual SHA-256. Recompute the declared input digest
   from ordered `reference|sha256:digest` lines. A revised task uses new Flow run,
   request, attempt, and idempotency identities. Preserve all parent files.

3. Review and explicitly approve that exact snapshot and complete Flow request.
   Put this body in a local file, with the already-authorized project grant:

   ```json
   {
     "request_ref": "runtime/request-r2.json",
     "approval_key": "approve-task-example-r2",
     "authority": {
       "active": true,
       "principal_id": "YOUR_PRINCIPAL",
       "actor_id": "YOUR_AUTHENTICATED_ACTOR",
       "capability": "project:task:update",
       "scope": "project:YOUR_PROJECT"
     }
   }
   ```

   ```text
   moon run --target native cmd/moonflow_project_plan_adapter gateway-approve \
     --gateway http://127.0.0.1:PORT --session-env EXISTING_MOONPROJ_SESSION \
     --task PT-example --body approval-r2.json
   ```

   The service checks the signed task creator, grant, canonical snapshot, and
   current revision. It stores approval and audit records under the existing
   transaction lock without starting work or changing task acceptance. The
   gateway retains the exact returned command and immutable adapter binding.
   Replaying the same approval key recovers its historical receipt; it never
   upgrades that approval to a newer task. Changed content under the key conflicts.

4. Execute the exact approved digital plan through the gateway. The body contains
   `request_ref` and `result_ref`. Use `gateway-execute` with the same gateway,
   session, task and `--body` flags. The gateway rereads the persisted approval
   command through the signed service, then checks current canonical task
   content before calling the existing adapter. A second call reconciles the same
   immutable attempt/output. There is no background execution. A task changing
   during digital plan generation may leave a historical output; new report return
   still checks the task revision atomically and refuses to present it as current.

5. Prepare the immutable report with the existing local command:

   ```text
   moon run --target native cmd/moonflow_project_plan_adapter prepare-company-report \
     --workspace WORKSPACE --request runtime/request-r2.json \
     --result runtime/result-r2.json --report-key plan-r2 --date 2026-10-08 \
     --summary 'Prepared the revised digital plan' --evidence flow-review.json
   ```

   Review evidence is optional and stays exact by reference and digest. The report
   does not reinterpret Flow acceptance as company or customer acceptance. It
   includes the approved binding and approval key alongside exact result and
   output evidence. Progress defaults to zero.

6. Return the saved report. The body file now contains only
   `{"request_ref":"runtime/request-r2.json"}`:

   ```text
   moon run --target native cmd/moonflow_project_plan_adapter gateway-return \
     --gateway http://127.0.0.1:PORT --session-env EXISTING_MOONPROJ_SESSION \
     --task PT-example --report-key plan-r2 --body report-return.json
   ```

   `gateway-status` with those same flags reopens reporting state. The gateway
   submits only the saved report body and its saved idempotency key to the existing
   `/api/company/plan/tasks/<task>/report` route. It never invokes the adapter while
   returning or retrying a report. First application requires the same canonical
   task revision and persisted approval under the transaction lock. An exact
   lost-ack replay uses the historical canonical request even if the task later
   changes. A reused key with changed report content conflicts.

## Recovery boundaries

- Approval persisted remotely but acknowledgement lost: repeat the same approval
  operation and key. No new execution is authorized by the timeout.
- Local approval file persisted but binding absent: repeat approval recording;
  the same receipt repairs the missing binding. Corrupt partial files fail closed.
- Adapter acknowledgement lost: use its existing execute/reconcile identity.
  A different revision requires a new binding and fresh approval.
- Report acknowledgement lost: status stays `pending_report`; retry the saved
  report. A complete matching service command alone changes it to `reported`.
- Task, Flow identity, input digest, artifact bytes, evidence, actor, report
  revision, or returned command mismatch: stop and preserve the earlier files.
- A complete report receipt is historical evidence and remains readable after
  the task changes. It does not authorize new work or mutate prior acceptance.

## API and qualification

Ordinary offline `execute` and `reconcile` explicitly refuse v2 revised-task
inputs before creating intent or output, even with a shape-valid local approval
file. They remain available for the separate legacy/unbound workflow. The v2
adapter execution entry itself performs authenticated HTTP approval and current
snapshot reads using the gateway's existing configured service identity; it has
no caller-supplied verified-JSON shortcut.

Offline v2 report inspection returns `reported_local_cache`, with an explicit
unverified-cache acknowledgement label. The gateway only returns `reported`
after independently rereading the exact persisted report command from the signed
company service. A missing, unavailable or conflicting service record cannot be
promoted by a fabricated local receipt. Such a cache blocks return/status until
the discrepancy is inspected; it does not trigger another adapter execution.

The normal CLI commands wrap these existing-gateway extensions:

- `GET /api/company/plan/tasks/<task>/flow-snapshot`
- `POST /api/company/plan/tasks/<task>/flow-bindings`
- `POST /api/company/plan/tasks/<task>/flow-execute`
- `POST /api/company/plan/tasks/<task>/flow-reports/<key>/return`
- `POST /api/company/plan/tasks/<task>/flow-reports/<key>/status`

Native fixtures use the actual gateway handler, session checks, actor-signature
forwarding, adapter execution/persistence, exact service request normalizers,
transaction SQL generation, and MoonFlow submission/reconciliation/review/replay.
The company store and signing secrets in the HTTP fixture are synthetic. These
tests do not establish actual PostgreSQL restart/transaction behavior, configured
production identity, a deployed gateway, browser UX, provider execution, customer
delivery, or financial acceptance. Those remain separately qualified boundaries.
