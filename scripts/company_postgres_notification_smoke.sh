#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4270}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-notification-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-notification-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-notification.XXXXXX")
PID=""
SUFFIX=$(/bin/date +%s)
CREATE_KEY="notify-sub-create-$SUFFIX"
UPDATE_KEY="notify-sub-update-$SUFFIX"
DELETE_KEY="notify-sub-delete-$SUFFIX"
READ_KEY="notify-message-read-$SUFFIX"
READ_ALL_KEY="notify-message-all-$SUFFIX"
MESSAGE_GUID="imported-message-$SUFFIX"
CONFIG_KEY="notify-config-$SUFFIX"
DISPATCH_KEY="notify-digest-dispatch-$SUFFIX"
WEBHOOK_TEST_KEY="notify-webhook-test-$SUFFIX"
EMAIL_TEST_KEY="notify-email-test-$SUFFIX"
EMAIL_REDELIVER_KEY="notify-email-redeliver-$SUFFIX"
EMAIL_EID="email-outbox-$SUFFIX"

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
    PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c \
    "DELETE FROM company_record WHERE source_id LIKE '%notification:%$SUFFIX%' OR source_id LIKE '%$CREATE_KEY%' OR source_id LIKE '%$UPDATE_KEY%' OR source_id LIKE '%$DELETE_KEY%' OR source_id LIKE '%$READ_KEY%' OR source_id LIKE '%$READ_ALL_KEY%' OR source_id = 'notification-source-$SUFFIX' OR source_id = 'notification-subscription-source-$SUFFIX' OR source_id = 'notification-webhook-param-$SUFFIX' OR source_id = 'notification-email-outbox-$SUFFIX' OR source_id LIKE '%$CONFIG_KEY%' OR source_id LIKE '%$DISPATCH_KEY%' OR source_id LIKE '%$WEBHOOK_TEST_KEY%' OR source_id LIKE '%$EMAIL_TEST_KEY%' OR source_id LIKE '%$EMAIL_REDELIVER_KEY%'; DELETE FROM company_aggregate_projection WHERE aggregate_id LIKE '%$SUFFIX%' OR source_event_id = 'notification:config_update:$CONFIG_KEY' OR source_event_id LIKE '%notification:digest_dispatch:$DISPATCH_KEY%' OR source_event_id LIKE '%notification:webhook_test:$WEBHOOK_TEST_KEY%' OR source_event_id LIKE '%notification:email_test:$EMAIL_TEST_KEY%' OR source_event_id LIKE '%notification:email_redeliver:$EMAIL_REDELIVER_KEY%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
  PGPASSWORD=${PGPASSWORD:-520825} PSQL_BIN="$PSQL_BIN" \
  MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
  "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1
psql -v ON_ERROR_STOP=1 -c "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/sys_message', 'notify-source-record-$SUFFIX', 1, '{\"msg_guid\":\"$MESSAGE_GUID\",\"user_id\":\"user-admin-0001\",\"title\":\"Native notification\",\"is_read\":false}'::jsonb, 'notification-source-$SUFFIX') ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/sys_warning_subscription', 'notify-subscription-source-record-$SUFFIX', 1, '{\"sub_id\":\"$SUFFIX\",\"user_id\":\"user-admin-0001\",\"channels\":\"email\",\"enabled\":true}'::jsonb, 'notification-subscription-source-$SUFFIX') ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/sys_param', 'notify-webhook-param-record-$SUFFIX', 1, '{\"pk\":\"notify.webhook.url\",\"pv\":\"https://example.invalid/webhook\"}'::jsonb, 'notification-webhook-param-$SUFFIX') ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/sys_email_outbox', 'notify-email-outbox-record-$SUFFIX', 1, '{\"eid\":\"$EMAIL_EID\",\"to_addr\":\"owner@example.com\",\"status\":\"failed\",\"subject\":\"Native source email\"}'::jsonb, 'notification-email-outbox-$SUFFIX') ON CONFLICT (source_id) DO NOTHING;" >/dev/null

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -sS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
    -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
    -H 'Content-Type: application/json' "$@"
}

body='{"ruleCode":"W005","bizType":"expense","severityMin":"warning","channels":["in_app","email"],"enabled":true}'
status=$(curl_common -o "$TMP_DIR/create.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $CREATE_KEY" --data "$body" "http://127.0.0.1:$PORT/api/company/notify/subscriptions")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.subId == "sub-'"$CREATE_KEY"'" and .data.delivery_effect == false and .data.providerExecution == false' "$TMP_DIR/create.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/replay.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $CREATE_KEY" --data "$body" "http://127.0.0.1:$PORT/api/company/notify/subscriptions")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.subId == .command.result.subId' "$TMP_DIR/replay.json" >/dev/null

curl_common "http://127.0.0.1:$PORT/api/company/notify/subscriptions" >"$TMP_DIR/list.json"
/usr/bin/jq -e '.data | any(.[]; .subId == "sub-'"$CREATE_KEY"'" and .ruleCode == "W005")' "$TMP_DIR/list.json" >/dev/null

curl_common "http://127.0.0.1:$PORT/api/company/notify/messages?status=unread" >"$TMP_DIR/messages-unread-before.json"
/usr/bin/jq -e '.data.total == 1 and (.data.rows | any(.[]; .msg_guid == "'"$MESSAGE_GUID"'"))' "$TMP_DIR/messages-unread-before.json" >/dev/null
curl_common "http://127.0.0.1:$PORT/api/company/notify/messages?status=read" >"$TMP_DIR/messages-read-before.json"
/usr/bin/jq -e '.data.total == 0' "$TMP_DIR/messages-read-before.json" >/dev/null

update_body='{"ruleCode":"W006","enabled":false}'
status=$(curl_common -o "$TMP_DIR/update.json" -w '%{http_code}' -X PATCH -H "Idempotency-Key: $UPDATE_KEY" --data "$update_body" "http://127.0.0.1:$PORT/api/company/source/notify/subscriptions/sub-$CREATE_KEY")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.ruleCode == "W006" and .data.enabled == false and .data.channels == ["in_app","email"]' "$TMP_DIR/update.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/delete.json" -w '%{http_code}' -X DELETE -H "Idempotency-Key: $DELETE_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/notify/subscriptions/sub-$CREATE_KEY")
test "$status" = 200
/usr/bin/jq -e '.data.state == "deleted" and .data.delivery_effect == false' "$TMP_DIR/delete.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/read.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $READ_KEY" "http://127.0.0.1:$PORT/api/company/source/notify/messages/$MESSAGE_GUID/read")
test "$status" = 200
/usr/bin/jq -e '.data.messageGuid == "'"$MESSAGE_GUID"'" and .data.isRead == true' "$TMP_DIR/read.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/read-all.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $READ_ALL_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/notify/messages/read-all")
test "$status" = 200
/usr/bin/jq -e '.data.state == "read" and .data.delivery_effect == false' "$TMP_DIR/read-all.json" >/dev/null

curl_common "http://127.0.0.1:$PORT/api/company/source/notify/messages" >"$TMP_DIR/messages.json"
/usr/bin/jq -e '.data.total == 1 and (.data.rows | any(.[]; .msg_guid == "'"$MESSAGE_GUID"'" and (.is_read == 1 or .isRead == true)))' "$TMP_DIR/messages.json" >/dev/null
curl_common "http://127.0.0.1:$PORT/api/company/notify/messages?status=unread" >"$TMP_DIR/messages-unread-after.json"
/usr/bin/jq -e '.data.total == 0' "$TMP_DIR/messages-unread-after.json" >/dev/null
curl_common "http://127.0.0.1:$PORT/api/company/notify/messages?status=read" >"$TMP_DIR/messages-read-after.json"
/usr/bin/jq -e '.data.total == 1 and (.data.rows | any(.[]; .msg_guid == "'"$MESSAGE_GUID"'"))' "$TMP_DIR/messages-read-after.json" >/dev/null

config_body='{"notify.email.enabled":true,"ai.llm.key":"super-secret","unknown.option":"ignored"}'
status=$(curl_common -o "$TMP_DIR/config.json" -w '%{http_code}' -X PUT -H "Idempotency-Key: $CONFIG_KEY" --data "$config_body" "http://127.0.0.1:$PORT/api/company/source/notify/config")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.updated == 2 and (.data.entries | any(.[]; .key == "ai.llm.key" and .redacted == true and .value == null)) and (.data.entries | any(.[]; .key == "notify.email.enabled" and .value == "true")) and (.data | tostring | contains("super-secret") | not)' "$TMP_DIR/config.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/config-replay.json" -w '%{http_code}' -X PUT -H "Idempotency-Key: $CONFIG_KEY" --data "$config_body" "http://127.0.0.1:$PORT/api/company/notify/config")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.updated == 2' "$TMP_DIR/config-replay.json" >/dev/null

curl_common "http://127.0.0.1:$PORT/api/company/source/notify/config" >"$TMP_DIR/config-read.json"
/usr/bin/jq -e '(.data.configured | any(.[]; .key == "ai.llm.key" and .redacted == true and .value == null)) and (.data.configured | any(.[]; .key == "notify.email.enabled" and .value == "true")) and (.data | tostring | contains("super-secret") | not)' "$TMP_DIR/config-read.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/dispatch.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $DISPATCH_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/notify/digest/dispatch")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.sent == false and .data.dryRun == true and .data.userCount == 1 and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/dispatch.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/dispatch-replay.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $DISPATCH_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/source/notify/digest/dispatch")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.userCount == 1 and .data.sent == false' "$TMP_DIR/dispatch-replay.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/webhook-test.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $WEBHOOK_TEST_KEY" --data '{"title":"Native test","content":"dry-run"}' "http://127.0.0.1:$PORT/api/company/notify/config/test-webhook")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.ok == false and .data.dryRun == true and .data.wouldSend == true and .data.reason == "provider_execution_disabled" and .data.urlConfigured == true and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/webhook-test.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/webhook-test-replay.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $WEBHOOK_TEST_KEY" --data '{"title":"Native test","content":"dry-run"}' "http://127.0.0.1:$PORT/api/company/source/notify/config/test-webhook")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.wouldSend == true and .data.ok == false' "$TMP_DIR/webhook-test-replay.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/email-test.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $EMAIL_TEST_KEY" --data '{"to":"owner@example.com"}' "http://127.0.0.1:$PORT/api/company/notify/email-outbox/test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.queued == false and .data.wouldQueue == true and .data.dryRun == true and .data.toConfigured == true and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/email-test.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/email-redeliver.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $EMAIL_REDELIVER_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/source/notify/email-outbox/$EMAIL_EID/redeliver")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.found == true and .data.status == "failed" and .data.queued == false and .data.wouldRedeliver == true and .data.reason == "provider_execution_disabled" and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/email-redeliver.json" >/dev/null
source_status=$(psql -At -c "SELECT payload->>'status' FROM company_record WHERE source_id = 'notification-email-outbox-$SUFFIX'")
test "$source_status" = failed

status=$(curl_common -o "$TMP_DIR/invalid.json" -w '%{http_code}' -X POST -H "Idempotency-Key: notify-invalid-$SUFFIX" --data '{"channels":["sms"]}' "http://127.0.0.1:$PORT/api/company/notify/subscriptions")
test "$status" = 400

/usr/bin/printf '%s\n' 'native PostgreSQL notification message/subscription command smoke passed'
