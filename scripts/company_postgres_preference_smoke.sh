#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4210}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-preference-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-preference-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-preference.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PREF_KEY="moonproj-smoke"
SET_KEY="preference-set-$SMOKE_SUFFIX"
DELETE_KEY="preference-delete-$SMOKE_SUFFIX"
AGGREGATE_ID="$ACTOR:$PREF_KEY"
SET_EVENT="preference:set:$SET_KEY"
DELETE_EVENT="preference:delete:$DELETE_KEY"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE aggregate_type = 'user_preference' AND aggregate_id = '$AGGREGATE_ID'; DELETE FROM company_record WHERE source_id IN ('moonproj:command:$SET_KEY', 'moonproj:command:$DELETE_KEY', 'moonproj:audit:$SET_EVENT', 'moonproj:audit:$DELETE_EVENT');" \
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

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/sed 's/^.*= //')
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

set_body='{"value":{"theme":"native"}}'
status=$(/usr/bin/curl -sS -o "$TMP_DIR/set.json" -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $SET_KEY" \
  --data "$set_body" \
  "http://127.0.0.1:$PORT/api/company/source/auth/prefs/$PREF_KEY")
if [ "$status" != "200" ]; then
  /bin/cat "$TMP_DIR/set.json" "$TMP_DIR/service.log"
  exit 1
fi
/usr/bin/jq -e '.idempotent_replay == false and .preference.state == "active" and .preference.value.theme == "native" and .preference.authorizing == false and .preference.cash_effect == false and .preference.accounting_effect == false and .preference.tax_effect == false' "$TMP_DIR/set.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $SET_KEY" \
  --data "$set_body" \
  "http://127.0.0.1:$PORT/api/company/source/auth/prefs/$PREF_KEY")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .preference.state == "active"' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/auth/prefs?userCode=$ACTOR" >"$TMP_DIR/read.json"
/usr/bin/jq -e '.data["moonproj-smoke"].theme == "native" and .command_projection == true and .persisted == true' "$TMP_DIR/read.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/delete.json" -w '%{http_code}' \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $DELETE_KEY" \
  --data '{}' \
  "http://127.0.0.1:$PORT/api/company/source/auth/prefs/$PREF_KEY")
if [ "$status" != "200" ]; then
  /bin/cat "$TMP_DIR/delete.json" "$TMP_DIR/service.log"
  exit 1
fi
/usr/bin/jq -e '.idempotent_replay == false and .preference.state == "deleted" and .preference.cash_effect == false and .preference.accounting_effect == false and .preference.tax_effect == false' "$TMP_DIR/delete.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/auth/prefs?userCode=$ACTOR" >"$TMP_DIR/deleted-read.json"
/usr/bin/jq -e '(.data["moonproj-smoke"] // null) == null and .command_projection == true' "$TMP_DIR/deleted-read.json" >/dev/null

echo "native MoonBit preference set/delete/idempotency/readback smoke passed"
