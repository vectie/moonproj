#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4242}
DATABASE=${DATABASE:-moonproj}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-investment-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-investment-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-investment.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PROJECT_ID=proj-0001
VERSION_ID="investment-smoke-version-$SMOKE_SUFFIX"
SECOND_VERSION_ID="investment-smoke-delete-version-$SMOKE_SUFFIX"
INDEX_ID="investment-smoke-index-$SMOKE_SUFFIX"
VERSION_KEY="investment-smoke-version-$SMOKE_SUFFIX"
SECOND_VERSION_KEY="investment-smoke-second-version-$SMOKE_SUFFIX"
INDEX_KEY="investment-smoke-index-$SMOKE_SUFFIX"
INDEX_UPDATE_KEY="investment-smoke-index-update-$SMOKE_SUFFIX"
ACTIVATE_KEY="investment-smoke-activate-$SMOKE_SUFFIX"
INDEX_DELETE_KEY="investment-smoke-index-delete-$SMOKE_SUFFIX"
SECOND_DELETE_KEY="investment-smoke-second-delete-$SMOKE_SUFFIX"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'investment_version' AND aggregate_id IN ('$VERSION_ID', '$SECOND_VERSION_ID')) OR (aggregate_type = 'investment_index' AND aggregate_id = '$INDEX_ID'); DELETE FROM company_record WHERE source_id LIKE 'moonproj:command:investment-smoke-%$SMOKE_SUFFIX' OR source_id LIKE 'moonproj:audit:investment:%investment-smoke-%$SMOKE_SUFFIX%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
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
/usr/bin/jq -e '.capabilities | index("investment_excel_index_upsert_candidate") != null' "$TMP_DIR/health.json" >/dev/null
/usr/bin/jq -e '.capabilities | index("investment_excel_plan_line_import_candidate") != null' "$TMP_DIR/health.json" >/dev/null
/usr/bin/jq -e '.capabilities | index("investment_subject_mappings_candidate") != null' "$TMP_DIR/health.json" >/dev/null
/usr/bin/jq -e '.capabilities | index("investment_plan_line_update_candidate") != null' "$TMP_DIR/health.json" >/dev/null
/usr/bin/jq -e '.capabilities | index("investment_excel_upload_candidate") != null' "$TMP_DIR/health.json" >/dev/null

version_body="{\"versionGuid\":\"$VERSION_ID\",\"versionName\":\"Native Investment Smoke\",\"remark\":\"local command projection\",\"activate\":true}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/version.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $VERSION_KEY" \
  --data "$version_body" \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/versions")
test "$status" = 201
/usr/bin/jq -e '.idempotent_replay == false and .investment.versionGuid == "'$VERSION_ID'" and .investment.investment_effect == true and .investment.authorizing == false and .investment.cash_effect == false and .investment.accounting_effect == false and .investment.tax_effect == false' "$TMP_DIR/version.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/version-replay.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $VERSION_KEY" \
  --data "$version_body" \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/versions")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .investment.versionGuid == "'$VERSION_ID'"' "$TMP_DIR/version-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/versions" >"$TMP_DIR/versions.json"
/usr/bin/jq -e '.command_projection == true and (.data | any(.[]; .versionGuid == "'$VERSION_ID'" and .sourceKind == "command" and .isCurrent == true))' "$TMP_DIR/versions.json" >/dev/null

index_body="{\"indexGuid\":\"$INDEX_ID\",\"dimension\":\"investment\",\"fullCode\":\"Inv.Smoke\",\"indexName\":\"Smoke Investment\",\"unit\":\"万元\",\"indexValue\":123.45,\"remark\":\"created\"}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/index.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_KEY" \
  --data "$index_body" \
  "http://127.0.0.1:$PORT/api/company/investment/versions/$VERSION_ID/indices")
test "$status" = 201
/usr/bin/jq -e '.idempotent_replay == false and .investment.indexGuid == "'$INDEX_ID'" and .investment.investment_effect == true and .investment.authorizing == false' "$TMP_DIR/index.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-replay.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_KEY" \
  --data "$index_body" \
  "http://127.0.0.1:$PORT/api/company/investment/versions/$VERSION_ID/indices")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .investment.indexGuid == "'$INDEX_ID'"' "$TMP_DIR/index-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/investment/versions/$VERSION_ID/indices" >"$TMP_DIR/indices.json"
/usr/bin/jq -e '.command_projection == true and (.data | map(.items[]) | any(.indexGuid == "'$INDEX_ID'" and .sourceKind == "command" and .indexValue == 123.45))' "$TMP_DIR/indices.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-update.json" -w '%{http_code}' \
  -X PUT -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_UPDATE_KEY" \
  --data '{"indexValue":234.56,"remark":"updated"}' \
  "http://127.0.0.1:$PORT/api/company/investment/indices/$INDEX_ID")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .investment.indexGuid == "'$INDEX_ID'" and .investment.investment_effect == true' "$TMP_DIR/index-update.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/investment/versions/$VERSION_ID/indices" >"$TMP_DIR/indices-updated.json"
/usr/bin/jq -e '.data | map(.items[]) | any(.indexGuid == "'$INDEX_ID'" and .indexValue == 234.56 and .remark == "updated")' "$TMP_DIR/indices-updated.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/activate.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $ACTIVATE_KEY" \
  --data '{}' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/versions/$VERSION_ID/activate")
test "$status" = 200
/usr/bin/jq -e '.investment.versionGuid == "'$VERSION_ID'" and .investment.isCurrent == true' "$TMP_DIR/activate.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-delete.json" -w '%{http_code}' \
  -X DELETE -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_DELETE_KEY" \
  --data '{}' \
  "http://127.0.0.1:$PORT/api/company/investment/indices/$INDEX_ID")
test "$status" = 200
/usr/bin/jq -e '.investment.state == "deleted" and .investment.investment_effect == true' "$TMP_DIR/index-delete.json" >/dev/null

second_body="{\"versionGuid\":\"$SECOND_VERSION_ID\",\"versionName\":\"Delete Smoke\",\"activate\":false}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/second-version.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $SECOND_VERSION_KEY" \
  --data "$second_body" \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/versions")
test "$status" = 201

status=$(/usr/bin/curl -sS -o "$TMP_DIR/second-delete.json" -w '%{http_code}' \
  -X DELETE -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $SECOND_DELETE_KEY" \
  --data '{}' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/versions/$SECOND_VERSION_ID")
test "$status" = 200
/usr/bin/jq -e '.investment.state == "deleted" and .investment.versionGuid == "'$SECOND_VERSION_ID'"' "$TMP_DIR/second-delete.json" >/dev/null

MISSING_IMPORT_ID="investment-smoke-missing-import-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-upsert-missing.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{}' \
  "http://127.0.0.1:$PORT/api/company/investment/excel-imports/$MISSING_IMPORT_ID/index-upsert")
test "$status" = 404
/usr/bin/jq -e '.code == 43001 and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/index-upsert-missing.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-upsert-write-gate.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"dryRun":false,"force":true}' \
  "http://127.0.0.1:$PORT/api/company/investment/excel-imports/$MISSING_IMPORT_ID/index-upsert")
test "$status" = 409
/usr/bin/jq -e '.code == 46001 and .dry_run == false and .force == true and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/index-upsert-write-gate.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/plan-line-import-missing.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"replaceExisting":true}' \
  "http://127.0.0.1:$PORT/api/company/investment/excel-imports/$MISSING_IMPORT_ID/plan-lines/import")
test "$status" = 404
/usr/bin/jq -e '.code == 43001 and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/plan-line-import-missing.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/plan-line-import-write-gate.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"dryRun":false,"replaceExisting":true}' \
  "http://127.0.0.1:$PORT/api/company/investment/excel-imports/$MISSING_IMPORT_ID/plan-lines/import")
test "$status" = 409
/usr/bin/jq -e '.code == 46002 and .dry_run == false and .replace_existing == true and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/plan-line-import-write-gate.json" >/dev/null

MISSING_PROJECT_ID="investment-smoke-missing-project-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/subject-mappings-missing.json" -w '%{http_code}' \
  -X PUT -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"items":[{"key":"rate.R24","value":"0.022"}]}' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$MISSING_PROJECT_ID/subject-mappings")
test "$status" = 404
/usr/bin/jq -e '.code == 41001' "$TMP_DIR/subject-mappings-missing.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/subject-mappings-write-gate.json" -w '%{http_code}' \
  -X PUT -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"dryRun":false,"items":[{"key":"rate.R24","value":"0.022"}]}' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/subject-mappings")
test "$status" = 409
/usr/bin/jq -e '.code == 46003 and .dry_run == false and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/subject-mappings-write-gate.json" >/dev/null

MISSING_LINE_ID="investment-smoke-missing-line-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/plan-line-update-missing.json" -w '%{http_code}' \
  -X PUT -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"subject":"Smoke"}' \
  "http://127.0.0.1:$PORT/api/company/investment/plan-lines/$MISSING_LINE_ID")
test "$status" = 404
/usr/bin/jq -e '.code == 43001' "$TMP_DIR/plan-line-update-missing.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/plan-line-update-write-gate.json" -w '%{http_code}' \
  -X PUT -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{"dryRun":false,"subject":"Smoke"}' \
  "http://127.0.0.1:$PORT/api/company/investment/plan-lines/$MISSING_LINE_ID")
test "$status" = 409
/usr/bin/jq -e '.code == 46004 and .dry_run == false and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/plan-line-update-write-gate.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/excel-upload-gate.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  "http://127.0.0.1:$PORT/api/company/investment/projects/$PROJECT_ID/excel-imports")
test "$status" = 409
/usr/bin/jq -e '.code == 46005 and .data.multipartAccepted == false and .data.binaryParser == "not_connected" and .persisted == false and .provider_execution == false and .authorizing == false' "$TMP_DIR/excel-upload-gate.json" >/dev/null

echo "native MoonBit investment version/index lifecycle/idempotency/readback smoke passed"
