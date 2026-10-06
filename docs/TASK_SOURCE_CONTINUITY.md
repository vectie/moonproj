# Source-backed task and receipt continuity

Status: implemented source-level slice; configured PostgreSQL/runtime acceptance
is still required. This is not a live company, customer or cash result.

## Existing founder flow

1. Prepare work in the existing task form. “Source and problem” is optional.
   The source reference and observed problem stay with the ordinary local draft.
2. Create the task through the existing signed company gateway. Source context
   is part of the same canonical create request and its existing idempotency
   comparison. No second command family or authority grant is introduced.
3. Start the existing MoonClaw handoff. Source context is included in the
   reserved exact request bytes. Product-bound tasks also include it in their
   existing content-addressed context artifact. Retry uses the saved reservation.
4. Reopen the canonical task. The company task read route returns its source,
   original create brief, and existing command/audit records. Report receipts
   retain the exact selected execution source and internal Accept references.

Source context is creation-time metadata in this slice. Existing update
commands do not edit it. Task titles, scheduling and remarks retain their
existing update semantics. The original create brief stays inspectable even
after those fields change; each execution still uses its reserved input bytes.

## Compatibility

- Create accepts optional `source_context: {reference: string, problem: string}`.
  Each field permits up to 8,192 UTF-16 code units. Empty or absent context is
  omitted from the canonical request, preserving older request identities.
- There is no new mandatory evidence field or approval step. Unknown context
  keys are rejected so authority or credentials are not retained as structured
  source metadata. Users must not put secrets into ordinary text fields.
- Version-1 local drafts without the new optional fields still restore.
- Older task detail responses work without `source_context` or `commitment`.
  Imported tasks do not acquire synthetic signed command history.
- Native execution and product-context schema versions, shared library pins,
  report/acceptance command formats and existing adapter contracts are unchanged.

## Readback

`GET /api/company/tasks/:id` adds `data.commitment` for native command tasks.
The service reads the existing task/report company commands and left-joins their
actual audit rows, ordered by recorded time and event ID. No new business facts
are written by this read. It exposes only the original brief and selected
receipt identifiers/owners, never the command's authority object or credentials.

Missing or conflicting audit records stay visible beside the last known command
receipt. The task card displays source/problem directly; original brief and
technical receipt history remain under the existing collapsed identity section.

Customer acceptance and cash are explicitly `not_recorded_here`. Internal task
acceptance cannot populate either. Live PostgreSQL restart, Flow work-item
interoperability and provider/customer outcomes remain separate acceptance work.
