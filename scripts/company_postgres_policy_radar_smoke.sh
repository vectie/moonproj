#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4292}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-policy-radar-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-policy-owner}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-policy-radar-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-policy-radar.XXXXXX")
SERVICE_PID=""
SUFFIX=$(/bin/date +%s)
SOURCE_ID="beijing-changping-15th-five-year-plan-2026"
CHANGE_ID="compute-node-wording"
SOURCE_KEY="policy-source-review-$SUFFIX"
REJECT_KEY="policy-source-reject-$SUFFIX"
CHANGE_KEY="policy-change-review-$SUFFIX"
BLOCKED_KEY="policy-change-blocked-$SUFFIX"
SOURCE_EVENT="policy:source-review:$SOURCE_KEY"
REJECT_EVENT="policy:source-review:$REJECT_KEY"
CHANGE_EVENT="policy:change-review:$CHANGE_KEY"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE source_event_id IN ('$SOURCE_EVENT', '$REJECT_EVENT', '$CHANGE_EVENT'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$SOURCE_KEY', 'moonproj:audit:$SOURCE_EVENT', 'moonproj:command:$REJECT_KEY', 'moonproj:audit:$REJECT_EVENT', 'moonproj:command:$CHANGE_KEY', 'moonproj:audit:$CHANGE_EVENT');" \
    >/dev/null 2>&1 || true
  find "$TMP_DIR" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
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
    "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
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

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')

request() {
  /usr/bin/curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' \
    -H "X-Moonproj-Actor: $ACTOR" \
    -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
    -H 'Content-Type: application/json' \
    "$@"
}

request "http://127.0.0.1:$PORT/api/company/policy/radar" >"$TMP_DIR/initial.json"
/usr/bin/jq -e \
  '.schema == "moonproj.policy-radar-projection.v1" and .freshness == "stale" and (.sources | length) == 2 and (.opportunities | length) == 3' \
  "$TMP_DIR/initial.json" >/dev/null

review_body='{"decision":"confirmed","evidence":"PAGE 58 wording checked against rendered PDF","reviewed_at":"2026-08-10"}'
reject_body='{"decision":"rejected","evidence":"smoke test establishes a deterministic unverified source gate","reviewed_at":"2026-08-10"}'
status=$(request -o "$TMP_DIR/reject.json" -w '%{http_code}' \
  -X POST -H "Idempotency-Key: $REJECT_KEY" --data "$reject_body" \
  "http://127.0.0.1:$PORT/api/company/policy/sources/$SOURCE_ID/reviews")
test "$status" = 201

status=$(request -o "$TMP_DIR/blocked.json" -w '%{http_code}' \
  -X POST -H "Idempotency-Key: $BLOCKED_KEY" --data "$review_body" \
  "http://127.0.0.1:$PORT/api/company/policy/changes/$CHANGE_ID/reviews")
test "$status" = 409
/usr/bin/jq -e '.error | contains("source must be verified")' "$TMP_DIR/blocked.json" >/dev/null

source_body='{"decision":"verified","evidence":"publisher, canonical URL, publication date, and PDF pages checked","reviewed_at":"2026-08-10"}'
status=$(request -o "$TMP_DIR/source.json" -w '%{http_code}' \
  -X POST -H "Idempotency-Key: $SOURCE_KEY" --data "$source_body" \
  "http://127.0.0.1:$PORT/api/company/policy/sources/$SOURCE_ID/reviews")
test "$status" = 201
/usr/bin/jq -e \
  '.policy_review.decision == "verified" and .policy_review.legal_effect == false and .policy_review.procurement_effect == false and (.policy_review.audit_id | length) > 0' \
  "$TMP_DIR/source.json" >/dev/null

status=$(request -o "$TMP_DIR/change.json" -w '%{http_code}' \
  -X POST -H "Idempotency-Key: $CHANGE_KEY" --data "$review_body" \
  "http://127.0.0.1:$PORT/api/company/policy/changes/$CHANGE_ID/reviews")
test "$status" = 201
/usr/bin/jq -e \
  '.policy_review.decision == "confirmed" and .notification_draft.state == "draft" and .notification_draft.delivery_effect == false' \
  "$TMP_DIR/change.json" >/dev/null

request "http://127.0.0.1:$PORT/api/company/policy/radar" >"$TMP_DIR/final.json"
/usr/bin/jq -e --arg source "$SOURCE_ID" --arg change "$CHANGE_ID" \
  '(.sources | any(.source_id == $source and .verification_state == "verified")) and (.changes | any(.change_id == $change and .review_state == "confirmed" and .notification_state == "draft")) and (.review_receipts | length) >= 2' \
  "$TMP_DIR/final.json" >/dev/null

status=$(request -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST -H "Idempotency-Key: $SOURCE_KEY" --data "$source_body" \
  "http://127.0.0.1:$PORT/api/company/policy/sources/$SOURCE_ID/reviews")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/printf '%s\n' "PostgreSQL Policy Radar persistence smoke passed"
