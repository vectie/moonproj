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
reported as coverage for user-scoped reads. Configuration values are never
returned; only allow-listed configured-key status can be exposed, with
password/key/secret/token values redacted. Provider discovery is metadata-only
and always reports provider_execution=false.

## Not yet connected

The following source actions remain explicitly outside this read slice:

- configuration writes and webhook tests;
- digest dispatch, email test/redelivery, and provider test calls;
- notification outbox delivery, retry/consent policy, and workflow effects;
- production identity, browser acceptance, and owner reconciliation.

The parity matrix records subscription create/update/delete as
`connected_notification_subscription_command`; browser acceptance, managed
identity, notification-owner approval, and real delivery remain open. This is
source translation evidence, not a claim of notification delivery or
accounting impact.
