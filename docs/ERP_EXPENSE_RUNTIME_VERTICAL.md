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

This is a backend/runtime acceptance slice. The Rabbita expense form is still
fixture-backed until it receives a same-origin session/token configuration and
calls these endpoints; that UI connection is the next implementation item.

The managed production-service manifest remains intentionally read-only until
the command gateway receives its own provider, identity, audit, rollback, and
business-acceptance approvals.
