# Expense runtime vertical

This is the first connected company workflow, built against the existing
PostgreSQL catalog without inventing a second database schema.

## Contract

The authenticated local service is
`scripts/company_postgres_service.py`. Every request requires the configured
bearer token, forwarded HTTPS, and (for commands) an `Idempotency-Key`.

| Operation | Endpoint | Result |
|---|---|---|
| List latest claims | `GET /api/company/expenses` | Latest projection for each expense |
| Read one claim | `GET /api/company/expenses/:id` | 404 when absent |
| Create draft | `POST /api/company/expenses` | `draft` |
| Submit | `POST /api/company/expenses/:id/submit` | `draft → submitted` |
| Reject | `POST /api/company/expenses/:id/reject` | `submitted → rejected` |
| Resubmit | `POST /api/company/expenses/:id/resubmit` | `rejected → submitted` |
| Approve | `POST /api/company/expenses/:id/approve` | `submitted → approved` |

The command body is JSON. Creation requires `expense_id`, `employee_id`,
`summary`, positive integer `amount_minor`, and a three-letter `currency`; it
may also carry `project_id` and `cost_subject`. The service actor is taken
from service configuration, never trusted from the request body.

Each accepted command writes:

- one immutable `expense_claim` aggregate projection revision;
- one `company_command` receipt keyed by the idempotency key;
- one `company_audit_event` raw record with actor, command, state, revision,
  and event identity.

Replaying the same key returns the original receipt without a new projection
or audit event. Reusing a key for a different request, or taking an invalid
state transition, returns `409`; missing/invalid fields return `4xx`.

## Evidence

`scripts/company_postgres_service_smoke.py` creates a unique claim, replays
creation, submits it, rejects it, resubmits it, approves it, replays approval,
reads the final `approved` projection, and verifies an invalid transition is
rejected. The smoke also retains the missing-token and forwarded-TLS checks.

## Rabbita local path

The new-expense Rabbita form now exercises the complete local command loop
through `scripts/company_postgres_dev_gateway.py`: create draft, submit,
reject, resubmit, and approve. The gateway serves the browser bundle and
proxies same-origin `/api/` calls to the authenticated service, keeping
`MOONPROJ_SERVICE_TOKEN` server-side and converting the form's JSON
`idempotency_key` into the required `Idempotency-Key` header. The form
visibly moves through `未创建 → 草稿 → 已提交 → 已驳回 → 已提交 → 已批准` while
each PostgreSQL projection revision, command receipt, and audit event is
written.

This is deliberately a local adapter, not a production session model. The
remaining Rabbita route families are fixture-backed, the demo expense ID and
idempotency keys are fixed for a repeatable development probe, and production
identity/session/token integration remains a separate gate. A browser
acceptance run on the local gateway verified all five transitions; the final
projection was `approved` with five command receipts and five audit events,
and the probe rows were removed after verification.

The browser evidence is recorded in
`docs/ERP_EXPENSE_BROWSER_ACCEPTANCE.md`. The local gateway now establishes
an HttpOnly session and signs its actor assertion into the service boundary;
the managed production-service manifest remains intentionally read-only until
the command gateway receives its own provider, identity, audit, rollback, and
business-acceptance approvals.
