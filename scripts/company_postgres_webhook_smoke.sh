#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4280}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-webhook-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-webhook-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-webhook.XXXXXX")
PID=""
SUFFIX=$(/bin/date +%s)
CREATE_KEY="webhook-config-create-$SUFFIX"
UPDATE_KEY="webhook-config-update-$SUFFIX"
TEST_KEY="webhook-test-delivery-$SUFFIX"
TEST_EVENT_ID="webhook:test_delivery:feishu:$TEST_KEY"
SCAN_KEY="webhook-scan-overdue-$SUFFIX"
SCAN_EVENT_ID="webhook:scan_overdue:$SCAN_KEY"

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
    PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c \
    "DELETE FROM company_record WHERE source_id LIKE '%$CREATE_KEY%' OR source_id LIKE '%$UPDATE_KEY%' OR source_id LIKE '%$TEST_KEY%' OR source_id LIKE '%$SCAN_KEY%' OR source_id LIKE '%webhook:config_update:%$SUFFIX%' OR source_id LIKE '%webhook:test_delivery:%$SUFFIX%' OR source_id LIKE '%webhook:scan_overdue:%$SUFFIX%' OR source_id LIKE '%webhook-source-$SUFFIX%'; DELETE FROM company_aggregate_projection WHERE aggregate_type IN ('webhook_config', 'webhook_test_delivery', 'webhook_overdue_scan') AND source_event_id LIKE '%$SUFFIX%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
  PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} PSQL_BIN="$PSQL_BIN" \
  MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
  "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1
psql -v ON_ERROR_STOP=1 -c "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/sys_param', 'webhook-param-$SUFFIX-1', 1, '{\"pk\":\"notify.webhook.dingtalk.enabled\",\"pv\":\"1\"}'::jsonb, 'webhook-source-$SUFFIX-1'), ('legacy/raw/sys_param', 'webhook-param-$SUFFIX-2', 1, '{\"pk\":\"notify.webhook.dingtalk.url\",\"pv\":\"https://imported.example.invalid/hook\"}'::jsonb, 'webhook-source-$SUFFIX-2'), ('legacy/raw/sys_param', 'webhook-param-$SUFFIX-3', 1, '{\"pk\":\"notify.webhook.dingtalk.secret\",\"pv\":\"importedsecret\"}'::jsonb, 'webhook-source-$SUFFIX-3'), ('legacy/raw/sys_warning', 'webhook-warning-$SUFFIX', 1, '{\"warning_guid\":\"webhook-warning-$SUFFIX\",\"title\":\"Webhook overdue warning\",\"severity\":\"warning\"}'::jsonb, 'webhook-source-$SUFFIX-4'), ('legacy/raw/sys_warning_ticket', 'webhook-ticket-$SUFFIX', 1, '{\"ticket_id\":\"webhook-ticket-$SUFFIX\",\"warning_guid\":\"webhook-warning-$SUFFIX\",\"assignee_user_id\":\"user-admin-0001\",\"due_date\":\"2020-01-01\",\"status\":\"open\"}'::jsonb, 'webhook-source-$SUFFIX-5') ON CONFLICT (source_id) DO NOTHING;" >/dev/null

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -sS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
    -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
    -H 'Content-Type: application/json' "$@"
}

body='{"enabled":true,"url":"https://hooks.example.invalid/secret-path","secret":"super-secret"}'
status=$(curl_common -o "$TMP_DIR/create.json" -w '%{http_code}' -X PUT -H "Idempotency-Key: $CREATE_KEY" --data "$body" "http://127.0.0.1:$PORT/api/company/source/webhook/config/feishu")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.platform == "feishu" and .data.enabled == true and .data.urlConfigured == true and .data.hasSecret == true and (.data | tostring | contains("super-secret") | not) and (.data | tostring | contains("hooks.example.invalid") | not)' "$TMP_DIR/create.json" >/dev/null

test_body='{"title":"Native webhook test","content":"dry-run only"}'
status=$(curl_common -o "$TMP_DIR/test-delivery.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $TEST_KEY" --data "$test_body" "http://127.0.0.1:$PORT/api/company/webhook/test/feishu")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.platform == "feishu" and .data.dryRun == true and .data.wouldSend == true and .data.skipped == "provider_execution_disabled" and .data.providerExecution == false and .data.delivery_effect == false and (.data | tostring | contains("super-secret") | not) and (.data | tostring | contains("hooks.example.invalid") | not)' "$TMP_DIR/test-delivery.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/test-delivery-replay.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $TEST_KEY" --data "$test_body" "http://127.0.0.1:$PORT/api/company/source/webhook/test/feishu")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.platform == "feishu" and .data.wouldSend == true' "$TMP_DIR/test-delivery-replay.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/replay.json" -w '%{http_code}' -X PUT -H "Idempotency-Key: $CREATE_KEY" --data "$body" "http://127.0.0.1:$PORT/api/company/webhook/config/feishu")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.platform == "feishu"' "$TMP_DIR/replay.json" >/dev/null

update_body='{"enabled":false,"secret":"__keep__"}'
status=$(curl_common -o "$TMP_DIR/update.json" -w '%{http_code}' -X PUT -H "Idempotency-Key: $UPDATE_KEY" --data "$update_body" "http://127.0.0.1:$PORT/api/company/source/webhook/config/feishu")
test "$status" = 200
/usr/bin/jq -e '.data.enabled == false and .data.urlConfigured == true and .data.hasSecret == true and (.data.updatedFields | index("url")) == null' "$TMP_DIR/update.json" >/dev/null

curl_common "http://127.0.0.1:$PORT/api/company/source/webhook/config" >"$TMP_DIR/read.json"
/usr/bin/jq -e '.data.feishu.enabled == false and .data.feishu.url == "" and .data.feishu.urlConfigured == true and .data.feishu.hasSecret == true and .data.dingtalk.enabled == true and .data.dingtalk.url == "已配置（已脱敏）" and .data.dingtalk.secret == "imp****ret" and .secret_values_redacted == true and (.data | tostring | contains("super-secret") | not) and (.data | tostring | contains("importedsecret") | not)' "$TMP_DIR/read.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/preview.json" -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/api/company/source/webhook/scan-overdue/preview")
test "$status" = 200
/usr/bin/jq -e '.data.scanned == 1 and .data.sent == false and .data.dryRun == true and .data.platforms == ["dingtalk"] and (.data.payload.title | contains("1")) and (.data.payload.content | contains("Webhook overdue warning")) and .source_coverage.sys_warning_ticket == 1 and .provider_execution == false and .delivery_effect == false' "$TMP_DIR/preview.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/scan.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $SCAN_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/webhook/scan-overdue")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.data.scanned == 1 and .data.data.sent == false and .data.data.dryRun == true and .data.data.reason == "provider_execution_disabled" and .data.providerExecution == false and .data.delivery_effect == false and .data.ticketMutation == false' "$TMP_DIR/scan.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/scan-replay.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $SCAN_KEY" --data '{}' "http://127.0.0.1:$PORT/api/company/source/webhook/scan-overdue")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.data.scanned == 1 and .data.data.sent == false' "$TMP_DIR/scan-replay.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/invalid.json" -w '%{http_code}' -X PUT -H "Idempotency-Key: webhook-invalid-$SUFFIX" --data '{"enabled":true}' "http://127.0.0.1:$PORT/api/company/webhook/config/slack")
test "$status" = 400

/usr/bin/printf '%s\n' 'native PostgreSQL webhook configuration candidate smoke passed'
