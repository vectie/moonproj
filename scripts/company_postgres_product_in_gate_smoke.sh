#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4290}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-product-in-gate-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-product-owner}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-product-in-gate-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-product-in-gate.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PRODUCT="moonproj-smoke-$SMOKE_SUFFIX"
MARK_KEY="product-in-gate-mark-$SMOKE_SUFFIX"
INVALID_KEY="product-in-gate-invalid-$SMOKE_SUFFIX"
EVENT_ID="product-in-gate:mark:$MARK_KEY"

terminate_service() {
  if [ -z "$SERVICE_PID" ]; then
    return
  fi
  child_pids=$(/usr/bin/pgrep -P "$SERVICE_PID" 2>/dev/null || true)
  for child_pid in $child_pids; do
    kill "$child_pid" 2>/dev/null || true
  done
  kill "$SERVICE_PID" 2>/dev/null || true
  i=0
  while kill -0 "$SERVICE_PID" 2>/dev/null && [ "$i" -lt 20 ]; do
    /bin/sleep 0.1
    i=$((i + 1))
  done
  for child_pid in $child_pids; do
    kill -KILL "$child_pid" 2>/dev/null || true
  done
  kill -KILL "$SERVICE_PID" 2>/dev/null || true
  wait "$SERVICE_PID" 2>/dev/null || true
  SERVICE_PID=""
}

cleanup() {
  terminate_service
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE aggregate_type = 'product_in_gate' AND aggregate_id = '$PRODUCT'; DELETE FROM company_record WHERE source_id IN ('moonproj:command:$MARK_KEY', 'moonproj:audit:$EVENT_ID');" \
    >/dev/null 2>&1 || true
  find "$TMP_DIR" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM

start_service() {
  MOONPROJ_SERVICE_TOKEN="$TOKEN" \
  MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
  PSQL_BIN="$PSQL_BIN" \
  PGDATABASE="$DATABASE" \
  "$ROOT/scripts/company_postgres_service.sh" \
    --port "$PORT" \
    --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
  SERVICE_PID=$!
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
}

stop_service() {
  terminate_service
}

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/sed 's/^.*= //')
experiment_body='{"decision":"experiment","primary_value":"solution","segment":"owner-operated software company","workflow":"weekly release decision","decided_at":"2026-08-04","problem_evidence":["problem-1"],"commitment_evidence":[],"current_behavior_cost":"manual review consumes two owner-days","outcome_metric":"reduce review time from two days to two hours","adoption_path":"owner introduces and repeats the workflow weekly","unresolved_risks":"pilot retention is not yet observed","next_experiment":"run with two owners for four weeks","review_by":"2026-11-02"}'
invalid_pass_body='{"decision":"pass","primary_value":"solution","segment":"owner-operated software company","workflow":"weekly release decision","decided_at":"2026-08-04","problem_evidence":[],"commitment_evidence":[],"current_behavior_cost":"manual review consumes two owner-days","outcome_metric":"reduce review time","adoption_path":"owner repeats weekly","unresolved_risks":"commitment evidence is missing","next_experiment":"collect evidence","review_by":"2026-11-02"}'

start_service

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/products/$PRODUCT/in-gate" >"$TMP_DIR/missing.json"
/usr/bin/jq -e '.revision == 0 and .product_in_gate.decision == "unknown" and .product_in_gate.persisted == false and .product_in_gate.exit_gate_effect == false' "$TMP_DIR/missing.json" >/dev/null

status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/mark.json" -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $MARK_KEY" \
  --data "$experiment_body" \
  "http://127.0.0.1:$PORT/api/company/products/$PRODUCT/in-gate")
test "$status_code" = 201
/usr/bin/jq -e '.idempotent_replay == false and .product_in_gate.decision == "experiment" and .product_in_gate.primary_value == "solution" and .product_in_gate.owner == "product-owner" and .product_in_gate.persisted == true and .product_in_gate.exit_gate_effect == false' "$TMP_DIR/mark.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/products/$PRODUCT/in-gate" >"$TMP_DIR/read.json"
/usr/bin/jq -e '.revision == 1 and .product_in_gate.decision == "experiment" and .product_in_gate.persisted == true' "$TMP_DIR/read.json" >/dev/null

stop_service
start_service

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/products/$PRODUCT/in-gate" >"$TMP_DIR/restart-read.json"
/usr/bin/jq -e '.revision == 1 and .product_in_gate.decision == "experiment" and .product_in_gate.owner == "product-owner"' "$TMP_DIR/restart-read.json" >/dev/null

status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $MARK_KEY" \
  --data "$experiment_body" \
  "http://127.0.0.1:$PORT/api/company/products/$PRODUCT/in-gate")
test "$status_code" = 200
/usr/bin/jq -e '.idempotent_replay == true and .product_in_gate.decision == "experiment"' "$TMP_DIR/replay.json" >/dev/null

status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/invalid-pass.json" -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $INVALID_KEY" \
  --data "$invalid_pass_body" \
  "http://127.0.0.1:$PORT/api/company/products/$PRODUCT/in-gate")
test "$status_code" = 422
/usr/bin/jq -e '.error | contains("three problem receipts")' "$TMP_DIR/invalid-pass.json" >/dev/null

/usr/bin/printf '%s\n' "PostgreSQL product In-Gate persistence smoke passed"
