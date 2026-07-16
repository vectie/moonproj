#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4298}
GATEWAY_PORT=${GATEWAY_PORT:-4299}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-report-export-gateway-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-report-export-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-report-export-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-report-export-gateway-password}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-report-export-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""

cleanup() {
  if [ -n "$GATEWAY_PID" ]; then kill "$GATEWAY_PID" 2>/dev/null || true; wait "$GATEWAY_PID" 2>/dev/null || true; fi
  if [ -n "$SERVICE_PID" ]; then kill "$SERVICE_PID" 2>/dev/null || true; wait "$SERVICE_PID" 2>/dev/null || true; fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
"$ROOT/scripts/company_postgres_service.sh" --port "$SERVICE_PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="report-export-gateway-session" \
MOONPROJ_DEV_USER="$USER_CODE" \
MOONPROJ_DEV_PASSWORD="$PASSWORD" \
"$ROOT/scripts/company_postgres_gateway.sh" --port "$GATEWAY_PORT" --service-port "$SERVICE_PORT" --actor-id admin >"$TMP_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

ready=0
for i in $(seq 1 120); do
  if /usr/bin/curl -sS "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session.json" 2>/dev/null; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1

/usr/bin/curl -fsS -c "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  --data "{\"user_code\":\"$USER_CODE\",\"password\":\"$PASSWORD\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session/login" >"$TMP_DIR/login.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "admin"' "$TMP_DIR/login.json" >/dev/null

body='{"filename":"gateway-ai-stats","sheets":[{"name":"AI概览","columns":[{"label":"指标","field":"metric"},{"label":"数值","field":"value"}],"rows":[{"metric":"本月调用","value":"1286"},{"metric":"准确率","value":"86.2%"}]}]}'
status=$(/usr/bin/curl -sS -D "$TMP_DIR/headers.txt" -o "$TMP_DIR/export.xlsx" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "$body" "http://127.0.0.1:$GATEWAY_PORT/api/company/export/excel")
test "$status" = 200
/usr/bin/grep -qi '^Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' "$TMP_DIR/headers.txt"
/usr/bin/unzip -t "$TMP_DIR/export.xlsx" >/dev/null
/usr/bin/unzip -p "$TMP_DIR/export.xlsx" xl/worksheets/sheet1.xml | /usr/bin/grep -q '1286'

/usr/bin/printf '%s\n' 'native PostgreSQL XLSX gateway export smoke passed'
