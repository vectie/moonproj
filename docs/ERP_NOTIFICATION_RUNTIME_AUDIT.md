# ERP notification runtime audit

Recorded: 2026-07-14

The source ERP notification surface is broader than the designer inbox. Its
read routes cover user-scoped sys_message rows and unread counts,
sys_warning_subscription, parameterized sys_param configuration,
sys_email_outbox metadata, digest preview/log evidence, and LLM-provider
discovery. Delivery, provider calls, subscription mutation, and message
acknowledgement are separate authority-bearing actions.

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

The current PostgreSQL export has no imported rows for sys_message,
sys_warning_subscription, sys_param, sys_email_outbox, or
sys_warning_digest_log. It has five imported sys_user rows, which are
reported as coverage for user-scoped reads. Configuration values are never
returned; only allow-listed configured-key status can be exposed, with
password/key/secret/token values redacted. Provider discovery is metadata-only
and always reports provider_execution=false.

## Not yet connected

The following source actions remain explicitly outside this read slice:

- marking one/all messages read;
- subscription create/update/delete;
- configuration writes and webhook tests;
- digest dispatch, email test/redelivery, and provider test calls;
- notification outbox delivery, retry/consent policy, and workflow effects;
- production identity, browser acceptance, and owner reconciliation.

The parity matrix therefore records the two browser routes as
connected_notification_read, while the source mutation handlers remain
action items. This is source coverage evidence, not a claim of notification
delivery or accounting impact.
