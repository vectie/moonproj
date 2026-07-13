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

Rabbita `/ai-stats` loads the overview and activity reads. Successful empty
responses render explicit `无源记录` states; designer analytics remain a
transport-failure fallback only. Badge reads preserve the source shape and
return `byAi=false` when no confirmed source draft matches.

The current PostgreSQL export has no rows for `ai_draft`, `ai_query_log`,
`ai_correction_log`, `wf_step_action`, or `wf_process_instance`; it has five
imported users for optional identity labels. Responses report
`authorizing=false`, `persisted=false`, and `provider_execution=false`.
Question text is truncated in activity metadata, and draft field payloads are
reduced to field-name hints.

## Remaining gates

- AI intake, confirm, discard, query, explain, rule, approval-draft, and
  command routes remain unconnected mutations.
- LLM/OCR execution, remote provider credentials, prompt/data retention,
  correction writes, workflow auto-skip authority, and draft-to-business
  promotion remain separate decisions.
- Production identity, browser acceptance, source completeness, and AI-owner
  reconciliation are still required.
