#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4201}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-supplier-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-supplier-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-supplier.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
SUPPLIER_ID="SUP-MB-SMOKE-$SMOKE_SUFFIX"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
PSQL_BIN="$PSQL_BIN" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$PORT" \
  --database "$DATABASE" \
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
/usr/bin/jq -e '.capabilities | index("supplier_command") and index("source_supplier_command") and index("supplier_rescore_command") and index("source_supplier_rescore_command")' "$TMP_DIR/health.json" >/dev/null

request() {
  name=$1
  method=$2
  path=$3
  expected=$4
  body=${5:-}
  key=${6:-}
  actor_signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
  if [ -n "$body" ]; then
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" \
      -H "X-Moonproj-Actor-Signature: $actor_signature" \
      -H 'Content-Type: application/json' -H "Idempotency-Key: $key" \
      --data "$body" "http://127.0.0.1:$PORT$path")
  else
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H 'X-Forwarded-Proto: https' \
      "http://127.0.0.1:$PORT$path")
  fi
  if [ "$status" != "$expected" ]; then
    /bin/cat "$TMP_DIR/$name.json"
    /bin/cat "$TMP_DIR/service.log"
    echo "unexpected status for $name: $status (expected $expected)" >&2
    exit 1
  fi
}

create_body="{\"providerGuid\":\"$SUPPLIER_ID\",\"providerCode\":\"SUP-CODE-$SMOKE_SUFFIX\",\"providerName\":\"MoonBit supplier smoke\",\"mainCategoryCode\":\"CAT-SMOKE\",\"shortName\":\"Moon supplier\",\"legalPerson\":\"Owner\",\"businessScope\":\"Native supplier boundary\",\"contactPerson\":\"Contact\",\"contactPhone\":\"10086\",\"enabled\":true}"
request create POST /api/company/source/srm/providers 201 "$create_body" "supplier-create-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg id "$SUPPLIER_ID" '.success == true and .idempotent_replay == false and .data.providerGuid == $id and .provider.sourceKind == "command" and .provider.auditState == "draft"' "$TMP_DIR/create.json" >/dev/null

request replay POST /api/company/source/srm/providers 200 "$create_body" "supplier-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and .provider.sourceKind == "command"' "$TMP_DIR/replay.json" >/dev/null

request collision POST /api/company/source/srm/providers 409 \
  "{\"providerGuid\":\"$SUPPLIER_ID\",\"providerCode\":\"DIFFERENT\",\"providerName\":\"Different\",\"mainCategoryCode\":\"CAT-SMOKE\"}" \
  "supplier-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.error | contains("already used")' "$TMP_DIR/collision.json" >/dev/null

request detail GET "/api/company/srm/providers/$SUPPLIER_ID" 200
/usr/bin/jq -e --arg id "$SUPPLIER_ID" '.data.provider.providerGuid == $id and .data.provider.providerName == "MoonBit supplier smoke" and .data.provider.sourceKind == "command"' "$TMP_DIR/detail.json" >/dev/null

request update PUT "/api/company/source/srm/providers/$SUPPLIER_ID" 200 \
  '{"providerName":"Updated MoonBit supplier","evalResult":"reviewed"}' \
  "supplier-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .provider.providerName == "Updated MoonBit supplier" and .provider.evalResult == "已评审"' "$TMP_DIR/update.json" >/dev/null

request rescore POST /api/company/source/srm/providers/rescore-all 200 '{}' "supplier-rescore-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .data.total >= 1 and .data.updated >= 1 and .data.wouldUpdate >= 1 and .data.importedProtected >= 0 and .data.dryRun == false and .data.providerExecution == false and .persisted == true and .authorizing == false and .idempotent_replay == false' "$TMP_DIR/rescore.json" >/dev/null
request rescore_replay POST /api/company/source/srm/providers/rescore-all 200 '{}' "supplier-rescore-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .idempotent_replay == true and .data.dryRun == false and .persisted == true' "$TMP_DIR/rescore_replay.json" >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/supplier-risk-board" \
  | /usr/bin/jq -e --arg id "$SUPPLIER_ID" '.items | any(.[]; .supplier_id == $id and .score >= 0 and (.rating | length) == 1 and .source_kind == "command")' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/suppliers/$SUPPLIER_ID/risk" \
  | /usr/bin/jq -e --arg id "$SUPPLIER_ID" '.supplier_id == $id and .score >= 0 and (.rating | length) == 1 and .source_kind == "command"' >/dev/null

request submit_review POST "/api/company/suppliers/$SUPPLIER_ID/submit_review" 200 \
  '{}' "supplier-submit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.supplier.state == "pending_review"' "$TMP_DIR/submit_review.json" >/dev/null

request review POST "/api/company/suppliers/$SUPPLIER_ID/review" 200 \
  '{"evaluation":"qualified","reason":"native smoke review"}' "supplier-review-$SMOKE_SUFFIX"
/usr/bin/jq -e '.supplier.state == "active" and .supplier.evaluation == "qualified"' "$TMP_DIR/review.json" >/dev/null

request blacklist POST "/api/company/suppliers/$SUPPLIER_ID/blacklist" 200 \
  '{"reason":"native smoke blacklist"}' "supplier-blacklist-$SMOKE_SUFFIX"
/usr/bin/jq -e '.supplier.state == "blacklisted"' "$TMP_DIR/blacklist.json" >/dev/null

request void DELETE "/api/company/source/srm/providers/$SUPPLIER_ID" 200 \
  '{"reason":"archive native supplier"}' "supplier-void-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .provider.auditState == "voided" and .provider.enabled == false' "$TMP_DIR/void.json" >/dev/null

request providers GET /api/company/srm/providers 200
imported_id=$(/usr/bin/jq -r '.data[] | select(.sourceKind == "imported") | .providerGuid' "$TMP_DIR/providers.json" | /usr/bin/head -n 1)
if [ -n "$imported_id" ]; then
  request imported_guard PUT "/api/company/source/srm/providers/$imported_id" 409 \
    '{"providerName":"must remain read only"}' "supplier-imported-guard-$SMOKE_SUFFIX"
  /usr/bin/jq -e '.error | contains("read-only")' "$TMP_DIR/imported_guard.json" >/dev/null
fi

echo "native MoonBit supplier/provider source-alias/lifecycle smoke passed"
