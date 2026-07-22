#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4261}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-report-template-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-report-template-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-report-template.XXXXXX")
PID=""

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id LIKE '%report-template-smoke%'; DELETE FROM company_aggregate_projection WHERE aggregate_type = 'report_template' AND source_event_id LIKE '%report-template-smoke%';" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} PSQL_BIN="$PSQL_BIN" MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then break; fi
  /bin/sleep 1
done

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" -H 'Content-Type: application/json' "$@"
}

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/reports/templates/meta" >"$TMP_DIR/meta.json"
/usr/bin/jq -e '.data.tables | length == 10 and any(.[]; .name == "ep_project" and (.columns | length) == 5)' "$TMP_DIR/meta.json" >/dev/null

body='{"templateName":"Project development report","description":"Native report smoke","baseTable":"ep_project","columns":["proj_code","proj_name","proj_status"],"filters":[{"field":"proj_status","op":"=","value":"development"}],"orderBy":"proj_code asc","isShared":false}'
status=$(curl_common -sS -o "$TMP_DIR/create.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: report-template-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/reports/templates")
test "$status" = 201
/usr/bin/jq -e '.template.template_id | startswith("RPT-CMD-")' "$TMP_DIR/create.json" >/dev/null

status=$(curl_common -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: report-template-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/reports/templates")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .template.template_id == (.command.result.template_id)' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/reports/templates" >"$TMP_DIR/list.json"
/usr/bin/jq -e '.command_projection == true and .command_projection_count == 1 and (.data | any(.[]; .templateName == "Project development report" and .sourceKind == "command"))' "$TMP_DIR/list.json" >/dev/null

run_body='{"baseTable":"ep_project","columns":["proj_code","proj_name"],"filters":[{"field":"proj_status","op":"=","value":"development"}],"orderBy":"proj_code asc","limit":10}'
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' -X POST --data "$run_body" "http://127.0.0.1:$PORT/api/company/reports/templates/run" >"$TMP_DIR/run.json"
/usr/bin/jq -e '.data.sql_executed == false and .data.total == 1 and .data.rows[0].proj_code == "TJ-HHJY-001" and (.data.columns | length) == 2 and .persisted == false' "$TMP_DIR/run.json" >/dev/null

template_id=$(/usr/bin/jq -r '.template.template_id' "$TMP_DIR/create.json")
curl_common -fsS -X DELETE -H 'Idempotency-Key: report-template-smoke-delete' --data '{"reason":"cleanup"}' "http://127.0.0.1:$PORT/api/company/reports/templates/$template_id" >"$TMP_DIR/delete.json"
/usr/bin/jq -e '.template.template_id == "'"$template_id"'" and .template.state == "deleted" and .cash_effect == false' "$TMP_DIR/delete.json" >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/reports/templates" >"$TMP_DIR/after-delete.json"
/usr/bin/jq -e '([.data[] | select(.templateId == "'"$template_id"'")] | length) == 0 and .command_projection_count == 0' "$TMP_DIR/after-delete.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL report template command smoke passed'
