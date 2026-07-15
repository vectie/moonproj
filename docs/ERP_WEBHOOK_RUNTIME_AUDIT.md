# ERP Webhook runtime audit

Recorded: 2026-07-14

The source `/api/v1/webhook/config` route is an administrative metadata read over
`sys_param`. It describes the Feishu, DingTalk, and WeCom channels; it does not
itself send a message or scan overdue tickets.

## Connected read

The PostgreSQL service and read-model adapter expose:

- `/api/company/webhook/config` and `/api/company/source/webhook/config`

The response preserves the three-platform shape (`enabled`, `url`, `secret`,
`hasSecret`) and adds source coverage. URL and secret values are redacted;
`provider_execution=false`, `persisted=false`, and `authorizing=false` make
the boundary explicit. Rabbita `/webhook-config` loads the read and shows
empty-source state when the controlled export has no `sys_param` rows.

`PUT /api/company/webhook/config/:platform` and its `/source` alias now form a
signed super-user configuration-candidate boundary for `feishu`, `dingtalk`,
and `wecom`. It preserves the source `enabled`/optional URL/secret and
`__keep__` semantics, but persists only URL/secret configured status and
digests. Candidate writes are idempotent and audited; they return
`credentialsBound=false`, `providerExecution=false`, and no delivery,
accounting, cash, or tax effects.

## Remaining gates

- Managed credential binding remains unauthorised until production identity,
  `webhook:config` permission, credential storage, and owner acceptance are
  wired; the redacted candidate write is connected for migration evidence.
- Test delivery and overdue scans remain disabled; no provider call is made by
  the read adapter.
- Source ticket history, retry/deduplication evidence, provider credentials,
  production browser acceptance, and notification-owner reconciliation remain
  open.
