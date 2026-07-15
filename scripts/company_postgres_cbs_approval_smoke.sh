#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4260}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-cbs-approval-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-cbs-approval-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-cbs-approval.XXXXXX")
PID=""

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id LIKE '%cbs-approval-smoke%'; DELETE FROM company_aggregate_projection WHERE aggregate_id LIKE '%cbs-approval-smoke%';" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} PSQL_BIN="$PSQL_BIN" MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then break; fi
  /bin/sleep 1
done

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" -H 'Content-Type: application/json' "$@"
}

body='{"bizType":"Contract","threshold":100,"actorUserId":"user-admin-0001","description":"Native approval smoke"}'
status=$(curl_common -sS -o "$TMP_DIR/create.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: cbs-approval-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/cbs/approval-rules")
test "$status" = 201
/usr/bin/jq -e '.data.bizType == "Contract" and .data.threshold == 100 and .approval_configuration_effect == true and .authorization_effect == false and .authorizing == false' "$TMP_DIR/create.json" >/dev/null

status=$(curl_common -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: cbs-approval-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/cbs/approval-rules")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.ruleGuid == "cbs-approval-cbs-approval-smoke-create"' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/approval-rules?bizType=Contract" | /usr/bin/jq -e '.command_projection == true and (.data | any(.[]; .rule_guid == "cbs-approval-cbs-approval-smoke-create" and .threshold == 100))' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/approval-rules/pick?bizType=Contract&amount=150" | /usr/bin/jq -e '.command_projection == true and .data.actor_user_id == "user-admin-0001" and .data.threshold == 100' >/dev/null

curl_common -fsS -X PUT -H 'Idempotency-Key: cbs-approval-smoke-update' --data '{"threshold":50,"description":"Updated approval smoke"}' "http://127.0.0.1:$PORT/api/company/cbs/approval-rules/cbs-approval-cbs-approval-smoke-create" | /usr/bin/jq -e '.data.ruleGuid == "cbs-approval-cbs-approval-smoke-create" and .data.threshold == 50 and .approval_configuration_effect == true' >/dev/null
curl_common -fsS -X DELETE -H 'Idempotency-Key: cbs-approval-smoke-delete' "http://127.0.0.1:$PORT/api/company/cbs/approval-rules/cbs-approval-cbs-approval-smoke-create" | /usr/bin/jq -e '.data.ruleGuid == "cbs-approval-cbs-approval-smoke-create" and .approval_configuration_effect == true' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/approval-rules?bizType=Contract" | /usr/bin/jq -e '([.data[] | select(.rule_guid == "cbs-approval-cbs-approval-smoke-create")] | length) == 0' >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL CBS approval command smoke passed'
