#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4194}
GATEWAY_PORT=${GATEWAY_PORT:-4193}
TRUSTED_GATEWAY_PORT=${TRUSTED_GATEWAY_PORT:-4195}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-gateway-smoke-actor-secret}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
TRUSTED_GATEWAY_PID=""

cleanup() {
  if [ -n "$TRUSTED_GATEWAY_PID" ]; then
    kill "$TRUSTED_GATEWAY_PID" 2>/dev/null || true
    wait "$TRUSTED_GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$GATEWAY_PID" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
PSQL_BIN="${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}" \
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$SERVICE_PORT" \
  --database "${DATABASE:-moonproj}" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="gateway-smoke-session-secret" \
MOONPROJ_DEV_USER="gateway-smoke-user" \
MOONPROJ_DEV_PASSWORD="gateway-smoke-password" \
"$ROOT/scripts/company_postgres_gateway.sh" \
  --port "$GATEWAY_PORT" \
  --service-port "$SERVICE_PORT" >"$TMP_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl --max-time 2 -sS \
    "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session-ready.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/service.log"
  /bin/cat "$TMP_DIR/gateway.log"
  exit 1
fi

/usr/bin/curl --max-time 5 -sS \
  -H 'Content-Type: application/json' \
  -d '{"user_code":"gateway-smoke-user","password":"gateway-smoke-password"}' \
  -c "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session/login" >"$TMP_DIR/login.json"
/usr/bin/jq -e '.authenticated == true and .identity_source == "development_fixture"' \
  "$TMP_DIR/login.json" >/dev/null

/usr/bin/curl --max-time 5 -sS -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "rabbita-user"' \
  "$TMP_DIR/session.json" >/dev/null

/usr/bin/curl --max-time 5 -sS -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/summary" >"$TMP_DIR/summary.json"
/usr/bin/jq -e '.product == "moonproj-company" and .target == "postgresql" and .read_only == true' \
  "$TMP_DIR/summary.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/no_session.json" -w '%{http_code}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/summary")
test "$status" = 401
/usr/bin/jq -e '.authenticated == false and .error == "session required"' \
  "$TMP_DIR/no_session.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/not_allowed.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/summary")
test "$status" = 404

gateway_expense_suffix=$(/bin/date +%s)
gateway_expense_id="EXP-GW-SMOKE-$gateway_expense_suffix"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/expense-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-expense-create-$gateway_expense_suffix" \
  --data "{\"expense_id\":\"$gateway_expense_id\",\"employee_id\":\"rabbita-user\",\"summary\":\"gateway smoke expense\",\"amount_minor\":3210,\"currency\":\"CNY\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/expenses")
test "$status" = 201
/usr/bin/jq -e \
  '.idempotent_replay == false and .expense.expense_id == "'"$gateway_expense_id"'" and .expense.state == "draft"' \
  "$TMP_DIR/expense-create.json" >/dev/null

gateway_contract_suffix=$(/bin/date +%s)
gateway_contract_id="CT-GW-SMOKE-$gateway_contract_suffix"
gateway_contract_body="{\"contractGuid\":\"$gateway_contract_id\",\"contractCode\":\"C-GW-$gateway_contract_suffix\",\"contractName\":\"gateway smoke contract\",\"buGuid\":\"bu-gateway\",\"projGuid\":\"proj-gateway\",\"providerGuid\":\"supplier-gateway\",\"signDate\":\"2026-07-15\",\"htAmount\":88.80,\"rCode\":\"R1\",\"l3Code\":\"L3-GW\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/contract-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-contract-create-$gateway_contract_suffix" \
  --data "$gateway_contract_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/cost/contracts")
test "$status" = 201
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.contractGuid == "'"$gateway_contract_id"'" and .contract.state == "draft"' \
  "$TMP_DIR/contract-create.json" >/dev/null

/usr/bin/curl --max-time 5 -sS -b "$TMP_DIR/cookies.txt" -c "$TMP_DIR/cookies.txt" \
  -X POST "http://127.0.0.1:$GATEWAY_PORT/api/session/logout" >"$TMP_DIR/logout.json"
/usr/bin/jq -e '.authenticated == false' "$TMP_DIR/logout.json" >/dev/null

IDENTITY_SECRET="gateway-smoke-identity-secret"
MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="gateway-smoke-session-secret" \
MOONPROJ_UPSTREAM_IDENTITY_SECRET="$IDENTITY_SECRET" \
"$ROOT/scripts/company_postgres_gateway.sh" \
  --port "$TRUSTED_GATEWAY_PORT" \
  --service-port "$SERVICE_PORT" \
  --trusted-identity-secret-env MOONPROJ_UPSTREAM_IDENTITY_SECRET \
  >"$TMP_DIR/trusted-gateway.log" 2>&1 &
TRUSTED_GATEWAY_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl --max-time 2 -sS \
    "http://127.0.0.1:$TRUSTED_GATEWAY_PORT/api/session" >"$TMP_DIR/trusted-ready.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/trusted-gateway.log"
  exit 1
fi

timestamp=$(/bin/date +%s)
signature=$(
  /usr/bin/printf '%s:%s' limingjin "$timestamp" |
    /usr/bin/openssl dgst -sha256 -hmac "$IDENTITY_SECRET" -hex |
    /usr/bin/awk '{print $1}'
)
/usr/bin/curl --max-time 5 -sS -D "$TMP_DIR/trusted-headers.txt" \
  -X POST \
  -H "X-Moonproj-Identity: limingjin" \
  -H "X-Moonproj-Identity-Timestamp: $timestamp" \
  -H "X-Moonproj-Identity-Signature: $signature" \
  "http://127.0.0.1:$TRUSTED_GATEWAY_PORT/api/session/login" >"$TMP_DIR/trusted-login.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "limingjin" and .identity_source == "trusted_upstream"' \
  "$TMP_DIR/trusted-login.json" >/dev/null
/usr/bin/grep -qi 'set-cookie: moonproj_session=.*secure' "$TMP_DIR/trusted-headers.txt"

echo "native MoonBit gateway session/proxy/trusted-identity smoke passed"
