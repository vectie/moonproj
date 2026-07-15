#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4208}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-warning-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-warning-actor-secret}
RULE_ACTOR=${MOONPROJ_RULE_ACTOR_ID:-admin}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-warning.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
WARNING_GUID="source:W005:proj-0002"
COMMAND_KEY="warning-resolve-$SMOKE_SUFFIX"
EVENT_ID="warning:resolve:$COMMAND_KEY"
RULE_KEY="warning-rule-config-$SMOKE_SUFFIX"
RULE_EVENT_ID="warning:rule_config:$RULE_KEY"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'warning_state' AND aggregate_id = '$WARNING_GUID') OR (aggregate_type = 'warning_rule_config' AND aggregate_id = 'W005'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$COMMAND_KEY', 'moonproj:audit:$EVENT_ID', 'moonproj:command:$RULE_KEY', 'moonproj:audit:$RULE_EVENT_ID');" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$PORT" \
  --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
rule_signature=$(/usr/bin/printf '%s' "$RULE_ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' \
    "http://127.0.0.1:$PORT/api/health" >"$TMP_DIR/health.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/service.log"
  exit 1
fi

body='{"note":"native warning smoke"}'
status=$(/usr/bin/curl -sS -o "$TMP_DIR/resolve.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $COMMAND_KEY" \
  --data "$body" \
  "http://127.0.0.1:$PORT/api/company/warning/$WARNING_GUID/resolve")
if [ "$status" != "200" ]; then
  /bin/cat "$TMP_DIR/resolve.json" "$TMP_DIR/service.log"
  exit 1
fi
/usr/bin/jq -e '.idempotent_replay == false and .warning.state == "resolved" and .warning.persisted == true and .warning.authorizing == false and .warning.cashEffect == false' "$TMP_DIR/resolve.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/rule.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $RULE_KEY" \
  --data '{"enabled":false}' "http://127.0.0.1:$PORT/api/company/source/warning/rules/W005")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .warning.ruleCode == "W005" and .warning.enabled == false and .warning.authorizing == false and .warning.authorization_candidate == true' "$TMP_DIR/rule.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/rule-replay.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $RULE_KEY" \
  --data '{"enabled":false}' "http://127.0.0.1:$PORT/api/company/warning/rules/W005")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.enabled == false' "$TMP_DIR/rule-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/warning/rules" >"$TMP_DIR/rules.json"
/usr/bin/jq -e '.data | any(.[]; .ruleCode == "W005" and .enabled == false and .commandProjection == true and .sourceKind == "command")' "$TMP_DIR/rules.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $COMMAND_KEY" \
  --data "$body" \
  "http://127.0.0.1:$PORT/api/company/warning/$WARNING_GUID/resolve")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.state == "resolved"' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/warning?status=all" >"$TMP_DIR/list.json"
/usr/bin/jq -e '.data.rows[0].status == "resolved" and .data.rows[0].commandProjection == true and .command_projection_count == 1 and .persisted == true' "$TMP_DIR/list.json" >/dev/null

echo "native MoonBit warning resolve/idempotency/readback smoke passed"
