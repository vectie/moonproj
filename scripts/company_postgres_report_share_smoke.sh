#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4262}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-report-share-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-report-share-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-report-share.XXXXXX")
PID=""

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

TOKEN_ID=$(/usr/bin/printf '%s' "$ACTOR:cost:report-share-smoke-create" | /usr/bin/openssl dgst -sha256 -hex | /usr/bin/sed 's/^.*= //' | /usr/bin/cut -c 1-48)
cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id IN ('moonproj:command:report-share-smoke-create', 'moonproj:audit:report_share:create:report-share-smoke-create', 'moonproj:command:report-share-smoke-delete', 'moonproj:audit:report_share:delete:report-share-smoke-delete'); DELETE FROM company_aggregate_projection WHERE aggregate_type = 'report_share' AND aggregate_id = '$TOKEN_ID';" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# Keep reruns deterministic if a previous process was interrupted.
cleanup_stale() {
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id IN ('moonproj:command:report-share-smoke-create', 'moonproj:audit:report_share:create:report-share-smoke-create', 'moonproj:command:report-share-smoke-delete', 'moonproj:audit:report_share:delete:report-share-smoke-delete'); DELETE FROM company_aggregate_projection WHERE aggregate_type = 'report_share' AND aggregate_id = '$TOKEN_ID';" >/dev/null 2>&1 || true
}
cleanup_stale

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} PSQL_BIN="$PSQL_BIN" MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" -H 'Content-Type: application/json' "$@"
}

body='{"reportKey":"cost","expiresInDays":0,"title":"Native shared cost"}'
status=$(curl_common -sS -o "$TMP_DIR/create.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: report-share-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/reports/shares")
test "$status" = 201
/usr/bin/jq -e '.data.token | length == 48' "$TMP_DIR/create.json" >/dev/null
/usr/bin/jq -e '.data.reportKey == "cost" and .data.title == "Native shared cost" and .data.neverExpires == true and .cash_effect == false' "$TMP_DIR/create.json" >/dev/null

status=$(curl_common -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: report-share-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/reports/shares")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.token == (.command.result.token)' "$TMP_DIR/replay.json" >/dev/null

curl_common -fsS "http://127.0.0.1:$PORT/api/company/reports/shares" >"$TMP_DIR/list.json"
/usr/bin/jq -e '.data | any(.[]; .token == "'"$TOKEN_ID"'" and .reportKey == "cost" and .neverExpires == true and .revoked == false)' "$TMP_DIR/list.json" >/dev/null

# Public reads intentionally omit the bearer and actor headers; forwarded TLS remains required.
/usr/bin/curl -fsS -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/share/$TOKEN_ID/meta" >"$TMP_DIR/meta.json"
/usr/bin/jq -e '.data.reportKey == "cost" and .data.title == "Native shared cost" and .data.neverExpires == true and .authorizing == false' "$TMP_DIR/meta.json" >/dev/null
/usr/bin/curl -fsS -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/share/$TOKEN_ID/data" >"$TMP_DIR/data.json"
/usr/bin/jq -e '.data.rows | length >= 1' "$TMP_DIR/data.json" >/dev/null

curl_common -fsS "http://127.0.0.1:$PORT/api/company/reports/shares" >"$TMP_DIR/accessed.json"
/usr/bin/jq -e '.data | any(.[]; .token == "'"$TOKEN_ID"'" and .accessCount == 1 and .lastAccessAt != null)' "$TMP_DIR/accessed.json" >/dev/null

curl_common -fsS -X DELETE -H 'Idempotency-Key: report-share-smoke-delete' --data '{"reason":"smoke cleanup"}' "http://127.0.0.1:$PORT/api/company/reports/shares/$TOKEN_ID" >"$TMP_DIR/delete.json"
/usr/bin/jq -e '.data.token == "'"$TOKEN_ID"'" and .data.revoked == true and .tax_effect == false' "$TMP_DIR/delete.json" >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/revoked.json" -w '%{http_code}' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/share/$TOKEN_ID/meta")
test "$status" = 410
/usr/bin/jq -e '.success == false and .code == 40300' "$TMP_DIR/revoked.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL report share command/public read smoke passed'
