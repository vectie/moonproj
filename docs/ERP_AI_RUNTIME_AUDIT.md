# ERP AI analytics runtime audit

Recorded: 2026-07-14

The source AI analytics surface is an observation layer over confirmed AI
drafts, query logs, correction logs, workflow auto-skips, and imported users.
It is not an AI execution gateway. The target therefore preserves analytics
evidence only and never calls an LLM/OCR provider or promotes a draft.

## Connected reads

The PostgreSQL service and read-model adapter expose:

- `/api/company/ai-stats/overview?period=today|week|month`
- `/api/company/ai-stats/activity?limit=...`
- `/api/company/ai-stats/badge?bizType=...&bizGuid=...`
- `POST /api/company/ai-stats/badge/batch` (and the `/source` alias)

Rabbita `/ai-stats` loads the overview and activity reads. Successful empty
responses render explicit `无源记录` states; designer analytics remain a
transport-failure fallback only. Badge reads preserve the source shape and
return `byAi=false` when no confirmed source draft matches. Batch badge reads
preserve the source map shape, select only confirmed imported drafts, and
return an empty map for missing/invalid request fields.

The current PostgreSQL export has no rows for `ai_draft`, `ai_query_log`,
`ai_correction_log`, `wf_step_action`, or `wf_process_instance`; it has five
imported users for optional identity labels. Responses report
`authorizing=false`, `persisted=false`, and `provider_execution=false`.
Question text is truncated in activity metadata, and draft field payloads are
reduced to field-name hints.

## AI Hub observation boundary

The PostgreSQL service and read-model adapter also expose source-compatible
GET reads for `/api/company/ai-hub/corrections`, `/correction-stats`,
`/drafts`, `/drafts/:draftId`, `/query-log`, and `/usage-stats`. Rabbita
`/ai-hub` loads usage metrics, draft history, query history, correction
statistics, and correction rows before rendering the designer workbench.
Empty source tables are rendered as
successful `无源记录` state; they never cause a synthetic draft or query to be
created.

These reads cover the source `ai_draft`, `ai_query_log`,
`ai_correction_log`, `ai_query_session`, `ai_query_turn`, `audit_log`, and
`sys_user` tables. The current export has no AI Hub draft/query/correction or
session rows and no AI confirmation audit rows. Imported draft descriptions
and query questions are bounded; SQL, OCR text, and draft field values are
redacted, with field-name hints retained where available. Every response
reports `authorizing=false`, `persisted=false`, `provider_execution=false`,
and `query_execution=false`.

The signed `POST /api/company/ai-hub/explain` (and `/source` alias) is now a
deterministic explanation candidate over the caller-supplied table. It returns
the source `explain/provider/model` fields plus row count, but never invokes an
LLM, persists prompt data, or authorizes a business action. The dedicated
PostgreSQL smoke proves the boundary.

The nine AI Hub mutation routes (`intake`, `confirm`, `discard`, `query`,
`rule-from-nl`, `approval-draft`, `global-ask`, `query-session`, and
`command`) now have a signed command-gate candidate, including `/source`
aliases. The gate reports the requested command while keeping provider/query
execution, draft persistence, workflow authority, and financial effects false;
it does not consume or store the request body.

## Remaining gates

- AI intake, confirm, discard, query, rule, approval-draft, global-ask,
  query-session, and command routes remain explicit owner-gated candidates;
  durable mutations and provider execution are still disabled.
- Provider-backed AI Hub explanation remains gated behind browser and AI-owner
  acceptance; the current explanation route is deterministic only.
- LLM/OCR execution, remote provider credentials, prompt/data retention,
  correction writes, workflow auto-skip authority, and draft-to-business
  promotion remain separate decisions.
- Production identity, browser acceptance, source completeness, and AI-owner
  reconciliation are still required.
