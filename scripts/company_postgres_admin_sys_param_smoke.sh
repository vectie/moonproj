#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4282}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-admin-param-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-admin-param-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-admin-param.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PARAM_CODE="moonproj.smoke.$SMOKE_SUFFIX"
SECRET_CODE="moonproj.secret.$SMOKE_SUFFIX.key"
COMMAND_KEY="admin-param-$SMOKE_SUFFIX"
SECRET_KEY="admin-secret-$SMOKE_SUFFIX"
EVENT_ID="admin:sys_param:$COMMAND_KEY"
SECRET_EVENT_ID="admin:sys_param:$SECRET_KEY"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE aggregate_type = 'admin_sys_param' AND aggregate_id IN ('$PARAM_CODE', '$SECRET_CODE'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$COMMAND_KEY', 'moonproj:command:$SECRET_KEY', 'moonproj:audit:$EVENT_ID', 'moonproj:audit:$SECRET_EVENT_ID');" \
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

status=$(/usr/bin/curl -sS -o "$TMP_DIR/param.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\",\"code\":\"$PARAM_CODE\",\"value\":\"mock\"}" \
  "http://127.0.0.1:$PORT/api/company/admin/sys-param")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .admin.code == "'"$PARAM_CODE"'" and .admin.valueConfigured == true and .admin.valueRedacted == true and .admin.authorizing == false and .admin.provider_execution == false and .admin.cashEffect == false' "$TMP_DIR/param.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\",\"code\":\"$PARAM_CODE\",\"value\":\"mock\"}" \
  "http://127.0.0.1:$PORT/api/company/source/admin/sys-param")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .admin.code == "'"$PARAM_CODE"'"' "$TMP_DIR/replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/secret.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$SECRET_KEY\",\"code\":\"$SECRET_CODE\",\"value\":\"raw-secret-must-not-return\"}" \
  "http://127.0.0.1:$PORT/api/company/admin/sys-param")
test "$status" = 200
/usr/bin/jq -e '.admin.sensitive == true and .admin.valueRedacted == true and (.command.request.value == null) and (.command.request.value_digest != null)' "$TMP_DIR/secret.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/invalid.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"admin-param-invalid","code":"bad key","value":"x"}' \
  "http://127.0.0.1:$PORT/api/company/admin/sys-param")
test "$status" = 400

echo "native MoonBit admin sys-param candidate/redaction/idempotency smoke passed"
