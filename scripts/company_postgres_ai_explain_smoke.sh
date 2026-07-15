#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4273}
DATABASE=${DATABASE:-moonproj}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-ai-explain-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-ai-explain-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-ai-explain.XXXXXX")
SERVICE_PID=""

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
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

headers="Authorization: Bearer $TOKEN"
cash_body='{"series":[{"ym":"2026-08","inflow":100,"outflow":140,"net":-40,"cumulativeNet":-40}],"gapWeeks":[{"weekStart":"2026-08-03","gap":25,"out":80,"in":55}]}'
/usr/bin/curl -fsS -o "$TMP_DIR/cashflow.json" -X POST \
  -H "$headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data "$cash_body" \
  "http://127.0.0.1:$PORT/api/company/cashflow/ai-explain"
/usr/bin/jq -e '.success == true and .data.provider == "native-deterministic" and .data.gapWeekCount == 1 and .provider_execution == false and .persisted == false and .authorizing == false and (.data.explain | contains("1"))' "$TMP_DIR/cashflow.json" >/dev/null

/usr/bin/curl -fsS -o "$TMP_DIR/investment.json" -X POST \
  -H "$headers" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' --data '{}' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/proj-0001/ai-explain"
/usr/bin/jq -e '.success == true and .data.provider == "native-deterministic" and .data.revenue == 18500 and .data.netProfit == 2890 and .provider_execution == false and .persisted == false and .authorizing == false' "$TMP_DIR/investment.json" >/dev/null

echo "native PostgreSQL cashflow/investment AI explanation candidate smoke passed"
