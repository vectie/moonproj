# ERP notification runtime audit

Recorded: 2026-07-14

The source ERP notification surface is broader than the designer inbox. Its
read routes cover user-scoped sys_message rows and unread counts,
sys_warning_subscription, parameterized sys_param configuration,
sys_email_outbox metadata, digest preview/log evidence, and LLM-provider
discovery. Delivery and provider calls are separate authority-bearing actions.
Self-scoped subscription mutations and message acknowledgement have bounded
local command seams; they do not deliver notifications or change company
configuration.

## Connected read boundary

The local PostgreSQL service and read-model adapter expose:

- /api/company/notify/messages and /messages/unread-count
- /api/company/notify/subscriptions
- /api/company/notify/config
- /api/company/notify/email-outbox
- /api/company/notify/digest/preview and /digest/log
- /api/company/notify/llm-providers

Rabbita /inbox loads the user-scoped message list and unread count. Rabbita
/notify-config chains subscriptions, redacted configuration keys, email
outbox metadata, digest preview/log rows, and provider discovery. Successful
empty responses are rendered as explicit 无源记录 states; designer rows
remain a transport-failure fallback only.

## Self-scoped subscription command boundary

`POST /api/company/source/notify/subscriptions` and `PATCH`/`DELETE`
`/api/company/source/notify/subscriptions/:id` bind the command to the signed
source `user_code`, validate the source channel vocabulary, and persist
idempotent `notification_subscription` revisions plus audit receipts. The
subscription read merges active local projections with imported rows and
filters local tombstones. Imported `sys_warning_subscription` rows remain
read-only. Command responses explicitly report `authorizing=false`,
`delivery_effect=false`, `provider_execution=false`, and no accounting, cash,
or tax effect. Native create/replay/read/update/delete evidence is covered by
the pure-shell PostgreSQL service smoke.

`POST /api/company/source/notify/messages/:guid/read` and
`POST /api/company/source/notify/messages/read-all` persist signed-user
read-state overlays. The overlay keeps imported `sys_message` rows immutable,
does not synthesize missing messages, and merges read state into the source
observation only when a matching imported message exists. Replay and empty
source read-all behavior are covered by the pure-shell service smoke.
The evidence script is `scripts/company_postgres_notification_smoke.sh`; it
also seeds one imported message to prove the overlay does not mutate the
source row and does not synthesize missing messages.

The current PostgreSQL export has no imported rows for sys_message,
sys_warning_subscription, sys_param, sys_email_outbox, or
sys_warning_digest_log. It has five imported sys_user rows, which are
reported as coverage for user-scoped reads. Secret configuration values are
never returned; only allow-listed configured-key status and non-secret
candidate values can be exposed, with password/key/secret/token values
redacted. Provider discovery is metadata-only and always reports
provider_execution=false.

`PUT /api/company/notify/config` (and the `/api/company/source` alias) is now a
signed super-user configuration-candidate boundary. It stores only an
allow-listed, redacted projection with idempotent replay and audit evidence;
`credentialsBound=false`, `providerExecution=false`, and delivery/accounting/
cash/tax effects remain false. The smoke script covers candidate write,
replay, readback, and secret redaction.

Signed super-user `POST /digest/dispatch` (and the `/source` alias) now
records an idempotent digest-dispatch candidate from imported warning and
recipient evidence. It returns bounded warning rows and recipient/count
metadata with `dryRun=true`, `sent=false`, and `delivery_effect=false`; it
does not enqueue in-app/email delivery or write source digest logs.

Signed super-user `POST /config/test-webhook` (and the `/source` alias) now
records an idempotent webhook-test candidate using the effective redacted
`notify.webhook.url`/kind state. It reports `wouldSend` and a stable skip
reason, but never exposes the URL, calls a provider, or creates a delivery
record.

Signed super-user `POST /email-outbox/test` and
`POST /email-outbox/:eid/redeliver` (including `/source` aliases) now record
idempotent email command candidates. Test candidates report a redacted
recipient and `wouldQueue=true`; redelivery candidates verify the imported
outbox status and report `wouldRedeliver` without changing that source row.
Neither operation inserts/updates `sys_email_outbox`, opens SMTP, or marks a
message delivered.

Signed super-user `POST /llm-test` (and the `/source` alias) now records a
redacted provider/model/key/endpoint candidate with `tested=false` and
`providerExecution=false`; it never invokes an LLM provider.

## Not yet connected

The following source actions remain explicitly outside this read slice:

- webhook tests; managed credential binding and provider configuration remain
  gated even though the redacted notification-config candidate write is
  connected;
- Actual LLM provider calls remain gated; digest dispatch, generic webhook
  test, email test/redelivery, and LLM test are persisted dry-run candidates;
- notification outbox delivery, retry/consent policy, and workflow effects;
- production identity, browser acceptance, and owner reconciliation.

The parity matrix records subscription create/update/delete as
`connected_notification_subscription_command`; browser acceptance, managed
identity, notification-owner approval, and real delivery remain open. This is
source translation evidence, not a claim of notification delivery or
accounting impact.
