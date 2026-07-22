#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4275}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-attachment-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-attachment-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-attachment.XXXXXX")
SERVICE_PID=""
cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
PSQL_BIN="$PSQL_BIN" "$ROOT/scripts/company_postgres_service.sh" \
  --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!
signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
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
/usr/bin/jq -e '.capabilities | index("attachment_re_extract_candidate")' "$TMP_DIR/health.json" >/dev/null
/usr/bin/jq -e '.capabilities | index("attachment_upload_candidate")' "$TMP_DIR/health.json" >/dev/null
/usr/bin/jq -e '.capabilities | index("attachment_delete_candidate")' "$TMP_DIR/health.json" >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/attachments/all" \
  | /usr/bin/jq -e '.success == true and .data.total >= 0 and (.data.rows | type) == "array"' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/source/attachments/list?bizType=expense" \
  | /usr/bin/jq -e '.success == true and (.data | type) == "array"' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/attachments/stats" \
  | /usr/bin/jq -e '.success == true and .data.total.count >= 0 and .data.total.bytes >= 0' >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/reextract.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  "http://127.0.0.1:$PORT/api/company/source/attachments/re-extract/missing-attachment")
test "$status" = 404
/usr/bin/jq -e '.success == false and .code == 43001 and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/reextract.json" >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/upload.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  "http://127.0.0.1:$PORT/api/company/attachments/upload")
test "$status" = 409
/usr/bin/jq -e '.code == 43002 and .data.multipartAccepted == false and .persisted == false and .authorizing == false' "$TMP_DIR/upload.json" >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/delete.json" -w '%{http_code}' -X DELETE \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  "http://127.0.0.1:$PORT/api/company/attachments/missing-attachment")
test "$status" = 409
/usr/bin/jq -e '.code == 43003 and .data.deleted == false and .persisted == false and .authorizing == false' "$TMP_DIR/delete.json" >/dev/null
echo "native PostgreSQL attachment read/upload/delete/re-extraction candidate smoke passed"
