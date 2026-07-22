#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4281}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-ai-stats-smoke-token}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-ai-stats.XXXXXX")
PID=""
SUFFIX=$(/bin/date +%s)
DRAFT_SOURCE="ai-stats-source-$SUFFIX"
GUID="contract-badge-$SUFFIX"

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
    PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c \
    "DELETE FROM company_record WHERE source_id LIKE '%$DRAFT_SOURCE%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
  PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} PSQL_BIN="$PSQL_BIN" \
  MOONPROJ_SERVICE_TOKEN="$TOKEN" \
  "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1

psql -v ON_ERROR_STOP=1 -c "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('legacy/raw/ai_draft', 'ai-draft-$SUFFIX', 1, '{\"draft_id\":\"ai-draft-$SUFFIX\",\"status\":\"confirmed\",\"biz_type\":\"contract\",\"result_biz_guid\":\"$GUID\",\"confidence\":0.92,\"llm_provider\":\"mock\",\"confirmed_at\":\"2026-01-01 00:00:00\"}'::jsonb, '$DRAFT_SOURCE') ON CONFLICT (source_id) DO NOTHING;" >/dev/null

body='{"bizType":"contract","bizGuids":["'"$GUID"'","missing-guid"]}'
status=$(/usr/bin/curl -sS -o "$TMP_DIR/batch.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H 'Content-Type: application/json' -X POST --data "$body" \
  "http://127.0.0.1:$PORT/api/company/source/ai-stats/badge/batch")
test "$status" = 200
/usr/bin/jq -e '.data["'"$GUID"'"].byAi == true and .data["'"$GUID"'"].confidence == 0.92 and .data["'"$GUID"'"].llmProvider == "mock" and .data.missing == null and .provider_execution == false and .persisted == false' "$TMP_DIR/batch.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/empty.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H 'Content-Type: application/json' -X POST --data '{}' \
  "http://127.0.0.1:$PORT/api/company/ai-stats/badge/batch")
test "$status" = 200
/usr/bin/jq -e '.data == {} and .authorizing == false and .provider_execution == false' "$TMP_DIR/empty.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL AI badge batch smoke passed'
