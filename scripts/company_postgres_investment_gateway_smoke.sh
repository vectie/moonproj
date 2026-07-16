#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4318}
GATEWAY_PORT=${GATEWAY_PORT:-4319}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-investment-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-investment-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-investment-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-investment-gateway-password}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD PSQL_BIN

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-investment-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
SUFFIX=$(/bin/date +%s)
VERSION_ID="investment-gateway-version-$SUFFIX"
SECOND_VERSION_ID="investment-gateway-delete-version-$SUFFIX"
INDEX_ID="investment-gateway-index-$SUFFIX"
VERSION_KEY="investment-gateway-version-$SUFFIX"
SECOND_VERSION_KEY="investment-gateway-second-version-$SUFFIX"
INDEX_KEY="investment-gateway-index-$SUFFIX"
INDEX_UPDATE_KEY="investment-gateway-index-update-$SUFFIX"
INDEX_DELETE_KEY="investment-gateway-index-delete-$SUFFIX"
ACTIVATE_KEY="investment-gateway-activate-$SUFFIX"
SECOND_DELETE_KEY="investment-gateway-second-delete-$SUFFIX"

cleanup() {
  if [ -n "$GATEWAY_PID" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'investment_version' AND aggregate_id IN ('$VERSION_ID', '$SECOND_VERSION_ID')) OR (aggregate_type = 'investment_index' AND aggregate_id = '$INDEX_ID'); DELETE FROM company_record WHERE source_id LIKE '%$SUFFIX%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" PSQL_BIN="$PSQL_BIN" \
  "$ROOT/scripts/company_postgres_service.sh" --port "$SERVICE_PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!
MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
  MOONPROJ_SESSION_SECRET="investment-gateway-session" MOONPROJ_DEV_USER="$USER_CODE" MOONPROJ_DEV_PASSWORD="$PASSWORD" \
  "$ROOT/scripts/company_postgres_gateway.sh" --port "$GATEWAY_PORT" --service-port "$SERVICE_PORT" --actor-id admin >"$TMP_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

ready=0
i=0
while [ "$i" -lt 120 ]; do
  if /usr/bin/curl -sS "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/service.log" "$TMP_DIR/gateway.log"
  exit 1
fi
/usr/bin/curl -fsS -c "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"user_code\":\"$USER_CODE\",\"password\":\"$PASSWORD\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session/login" >"$TMP_DIR/login.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "admin"' "$TMP_DIR/login.json" >/dev/null

version_body="{\"versionGuid\":\"$VERSION_ID\",\"versionName\":\"Gateway investment smoke\",\"activate\":false}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/version.json" -w '%{http_code}' -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $VERSION_KEY" --data "$version_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/versions")
test "$status" = 201
/usr/bin/jq -e --arg id "$VERSION_ID" '.idempotent_replay == false and .investment.versionGuid == $id and .investment.investment_effect == true and .investment.cash_effect == false' "$TMP_DIR/version.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/version-replay.json" -w '%{http_code}' -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $VERSION_KEY" --data "$version_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/versions")
test "$status" = 200
/usr/bin/jq -e --arg id "$VERSION_ID" '.idempotent_replay == true and .investment.versionGuid == $id' "$TMP_DIR/version-replay.json" >/dev/null

index_body="{\"indexGuid\":\"$INDEX_ID\",\"dimension\":\"investment\",\"fullCode\":\"Inv.Gateway\",\"indexName\":\"Gateway Investment\",\"unit\":\"万元\",\"indexValue\":10}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/index.json" -w '%{http_code}' -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_KEY" --data "$index_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/versions/$VERSION_ID/indices")
test "$status" = 201
/usr/bin/jq -e --arg id "$INDEX_ID" '.idempotent_replay == false and .investment.indexGuid == $id and .investment.authorizing == false' "$TMP_DIR/index.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-update.json" -w '%{http_code}' -X PUT -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_UPDATE_KEY" --data '{"indexValue":12,"remark":"gateway updated"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/indices/$INDEX_ID")
test "$status" = 200
/usr/bin/jq -e --arg id "$INDEX_ID" '.investment.indexGuid == $id and .investment.investment_effect == true' "$TMP_DIR/index-update.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/index-delete.json" -w '%{http_code}' -X DELETE -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $INDEX_DELETE_KEY" --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/indices/$INDEX_ID")
test "$status" = 200
/usr/bin/jq -e --arg id "$INDEX_ID" '.investment.indexGuid == $id and .investment.state == "deleted" and .investment.cash_effect == false' "$TMP_DIR/index-delete.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/activate.json" -w '%{http_code}' -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $ACTIVATE_KEY" --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/versions/$VERSION_ID/activate")
test "$status" = 200
/usr/bin/jq -e --arg id "$VERSION_ID" '.investment.versionGuid == $id and .investment.isCurrent == true and .investment.cash_effect == false' "$TMP_DIR/activate.json" >/dev/null

second_body="{\"versionGuid\":\"$SECOND_VERSION_ID\",\"versionName\":\"Gateway delete investment\",\"activate\":false}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/second-version.json" -w '%{http_code}' -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $SECOND_VERSION_KEY" --data "$second_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/versions")
test "$status" = 201
status=$(/usr/bin/curl -sS -o "$TMP_DIR/second-delete.json" -w '%{http_code}' -X DELETE -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $SECOND_DELETE_KEY" --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/versions/$SECOND_VERSION_ID")
test "$status" = 200
/usr/bin/jq -e --arg id "$SECOND_VERSION_ID" '.investment.versionGuid == $id and .investment.state == "deleted" and .investment.tax_effect == false' "$TMP_DIR/second-delete.json" >/dev/null

echo "native MoonBit investment gateway version/index lifecycle smoke passed"
