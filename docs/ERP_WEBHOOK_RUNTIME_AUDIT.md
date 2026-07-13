# ERP Webhook runtime audit

Recorded: 2026-07-14

The source `/api/v1/webhook/config` route is an administrative metadata read over
`sys_param`. It describes the Feishu, DingTalk, and WeCom channels; it does not
itself send a message or scan overdue tickets.

## Connected read

The PostgreSQL service and read-model adapter expose:

- `/api/company/webhook/config`

The response preserves the three-platform shape (`enabled`, `url`, `secret`,
`hasSecret`) and adds source coverage. URL and secret values are redacted;
`provider_execution=false`, `persisted=false`, and `authorizing=false` make
the boundary explicit. Rabbita `/webhook-config` loads the read and shows
empty-source state when the controlled export has no `sys_param` rows.

## Remaining gates

- Configuration writes remain unauthorised until production identity,
  `webhook:config` permission, audit evidence, and owner acceptance are wired.
- Test delivery and overdue scans remain disabled; no provider call is made by
  the read adapter.
- Source ticket history, retry/deduplication evidence, provider credentials,
  production browser acceptance, and notification-owner reconciliation remain
  open.
