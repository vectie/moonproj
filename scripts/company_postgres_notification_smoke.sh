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

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
    PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c \
    "DELETE FROM company_record WHERE source_id LIKE '%notification:%$SUFFIX%' OR source_id LIKE '%$CREATE_KEY%' OR source_id LIKE '%$UPDATE_KEY%' OR source_id LIKE '%$DELETE_KEY%' OR source_id LIKE '%$READ_KEY%' OR source_id LIKE '%$READ_ALL_KEY%' OR source_id = 'notification-source-$SUFFIX'; DELETE FROM company_aggregate_projection WHERE aggregate_id LIKE '%$SUFFIX%';" \
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
psql -v ON_ERROR_STOP=1 -c "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/sys_message', 'notify-source-record-$SUFFIX', 1, '{\"msg_guid\":\"$MESSAGE_GUID\",\"user_id\":\"user-admin-0001\",\"title\":\"Native notification\",\"is_read\":false}'::jsonb, 'notification-source-$SUFFIX') ON CONFLICT (source_id) DO NOTHING;" >/dev/null

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

status=$(curl_common -o "$TMP_DIR/invalid.json" -w '%{http_code}' -X POST -H "Idempotency-Key: notify-invalid-$SUFFIX" --data '{"channels":["sms"]}' "http://127.0.0.1:$PORT/api/company/notify/subscriptions")
test "$status" = 400

/usr/bin/printf '%s\n' 'native PostgreSQL notification message/subscription command smoke passed'
