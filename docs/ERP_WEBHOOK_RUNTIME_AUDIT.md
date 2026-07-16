# ERP Webhook runtime audit

Recorded: 2026-07-14

The source `/api/v1/webhook/config` route is an administrative metadata read over
`sys_param`. It describes the Feishu, DingTalk, and WeCom channels; it does not
itself send a message or scan overdue tickets.

## Connected read

The PostgreSQL service and read-model adapter expose:

- `/api/company/webhook/config` and `/api/company/source/webhook/config`
- `/api/company/webhook/test/:platform` and its `/source` alias
- `/api/company/webhook/scan-overdue/preview` and its `/source` alias

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

The trusted gateway now forwards canonical/source configuration candidates, and
Rabbita `/webhook-config` exposes the bounded WeCom save control. The gateway
smoke covers configuration replay and confirms that credentials remain
unbound.

The dry-run overdue preview now reads imported `sys_warning_ticket`,
`sys_warning`, `sys_user`, and webhook parameter evidence. It preserves the
source `no_overdue`, `no_platform_enabled`, and bounded preview payload states,
with `dryRun=true` only when a provider-enabled source platform and overdue
tickets are both present. It never updates tickets or sends a provider
request.

Signed super-user `POST /test/:platform` now records an idempotent
`webhook_test_delivery` candidate. It validates `feishu`, `dingtalk`, and
`wecom` configuration state and returns `dryRun=true`, `wouldSend`, and a
stable skip reason (`disabled`, `no_url`, or `provider_execution_disabled`),
without returning URL/secret values or making a provider request.
The native gateway now allow-lists canonical/source test aliases, and Rabbita
`/webhook-config` exposes a bounded “测试投递（干运行）” control for the WeCom
candidate. The gateway smoke proves signed super-user forwarding, replay, and
`providerExecution=false` with no external request.

Signed super-user `POST /scan-overdue` now records an idempotent
`webhook_overdue_scan` candidate from the same imported ticket window as the
preview. It returns the bounded source payload and platform/reason state with
`dryRun=true`, `sent=false`, and `ticketMutation=false`; it never updates
`last_webhook_notified_at` or calls a provider.

## Remaining gates

- Managed credential binding remains unauthorised until production identity,
  `webhook:config` permission, credential storage, and owner acceptance are
  wired; the redacted candidate write is connected for migration evidence.
- Test delivery and overdue scanning are now persisted dry-run candidates;
  actual provider delivery remains disabled, and no provider call is made by
  the native adapter.
- Source ticket history, retry/deduplication evidence, provider credentials,
  production browser acceptance, and notification-owner reconciliation remain
  open.
