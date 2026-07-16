#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4283}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-admin-dictionary-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-admin-dictionary-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-admin-dictionary.XXXXXX")
SERVICE_PID=""
SUFFIX=$(/bin/date +%s)
GROUP="moonproj_smoke_group_$SUFFIX"
CODE="option_$SUFFIX"
CREATE_KEY="admin-dict-create-$SUFFIX"
UPDATE_KEY="admin-dict-update-$SUFFIX"
SECRET_KEY="admin-dict-secret-$SUFFIX"
GUID="local-$CREATE_KEY"
SECRET_GUID="local-$SECRET_KEY"
CREATE_EVENT="admin:dict:create:$CREATE_KEY"
UPDATE_EVENT="admin:dict:update:$UPDATE_KEY"
SECRET_EVENT="admin:dict:create:$SECRET_KEY"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE aggregate_type = 'admin_dict_option' AND aggregate_id IN ('$GUID', '$SECRET_GUID'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$CREATE_KEY', 'moonproj:command:$UPDATE_KEY', 'moonproj:command:$SECRET_KEY', 'moonproj:audit:$CREATE_EVENT', 'moonproj:audit:$UPDATE_EVENT', 'moonproj:audit:$SECRET_EVENT');" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/awk '{print $1}')
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
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

common_headers="Authorization: Bearer $TOKEN"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/create.json" -w '%{http_code}' \
  -X POST -H "$common_headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$CREATE_KEY\",\"groupName\":\"$GROUP\",\"code\":\"$CODE\",\"value\":\"Smoke option\",\"displayOrder\":3}" \
  "http://127.0.0.1:$PORT/api/company/admin/dict/options")
test "$status" = 201
/usr/bin/jq -e '.idempotent_replay == false and .dictionary.groupName == "'"$GROUP"'" and .dictionary.code == "'"$CODE"'" and .dictionary.sourceKind == "command" and .dictionary.authorizing == false and .dictionary.cashEffect == false' "$TMP_DIR/create.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/read.json" -w '%{http_code}' \
  -H "$common_headers" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/admin/dict/options?groupName=$GROUP")
test "$status" = 200
/usr/bin/jq -e '.data | any(.[]; .paramGuid == "'"$GUID"'" and .sourceKind == "command" and .value == "Smoke option")' "$TMP_DIR/read.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/create-replay.json" -w '%{http_code}' \
  -X POST -H "$common_headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$CREATE_KEY\",\"groupName\":\"$GROUP\",\"code\":\"$CODE\",\"value\":\"Smoke option\",\"displayOrder\":3}" \
  "http://127.0.0.1:$PORT/api/company/source/admin/dict/options")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .dictionary.code == "'"$CODE"'"' "$TMP_DIR/create-replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/secret.json" -w '%{http_code}' \
  -X POST -H "$common_headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$SECRET_KEY\",\"groupName\":\"$GROUP\",\"code\":\"secret_token_$SUFFIX\",\"value\":\"raw-secret-must-not-return\"}" \
  "http://127.0.0.1:$PORT/api/company/admin/dict/options")
test "$status" = 201
/usr/bin/jq -e '.dictionary.value.valueRedacted == true and .dictionary.value.value == null and .command.request.value.value == null and .command.request.value.value_digest != null' "$TMP_DIR/secret.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/update.json" -w '%{http_code}' \
  -X PATCH -H "$common_headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"'"$UPDATE_KEY"'","enabled":false,"value":"Updated option","displayOrder":4}' \
  "http://127.0.0.1:$PORT/api/company/admin/dict/options/$GUID")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .dictionary.updated == 3 and .dictionary.enabled == false and .dictionary.value.value == "Updated option"' "$TMP_DIR/update.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/update-replay.json" -w '%{http_code}' \
  -X PATCH -H "$common_headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"'"$UPDATE_KEY"'","enabled":false,"value":"Updated option","displayOrder":4}' \
  "http://127.0.0.1:$PORT/api/company/source/admin/dict/options/$GUID")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .dictionary.enabled == false' "$TMP_DIR/update-replay.json" >/dev/null

echo "native MoonBit admin dictionary create/update/read/replay smoke passed"
