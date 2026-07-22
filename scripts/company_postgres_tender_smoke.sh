#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4243}
DATABASE=${DATABASE:-moonproj}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-tender-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-tender-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-tender.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
TENDER_ID="TD-SMOKE-$SMOKE_SUFFIX"
SOURCE_TENDER_ID="TD-SOURCE-SMOKE-$SMOKE_SUFFIX"
SPLIT_ID="SPLIT-SMOKE-$SMOKE_SUFFIX"
SOURCE_SPLIT_ID="SPLIT-SOURCE-SMOKE-$SMOKE_SUFFIX"
SUPPLIER_ID="SUP-TENDER-SMOKE-$SMOKE_SUFFIX"
PROJECT_ID="CD-HJL"

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
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >"$TMP_DIR/health.json" 2>/dev/null; then
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
/usr/bin/jq -e '.capabilities | index("tender_command") and index("source_tender_command") and index("source_tender_state_command") and index("source_tender_award_command") and index("contract_split_command") and index("source_contract_split_command")' "$TMP_DIR/health.json" >/dev/null

request() {
  name=$1
  method=$2
  path=$3
  expected=$4
  body=${5:-}
  key=${6:-}
  signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
  if [ -n "$body" ]; then
    status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
      -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
      -H 'Content-Type: application/json' -H "Idempotency-Key: $key" \
      --data "$body" "http://127.0.0.1:$PORT$path")
  else
    status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
      "http://127.0.0.1:$PORT$path")
  fi
  if [ "$status_code" != "$expected" ]; then
    /bin/cat "$TMP_DIR/$name.json"
    /bin/cat "$TMP_DIR/service.log"
    echo "unexpected status for $name: $status_code (expected $expected)" >&2
    exit 1
  fi
}

supplier_body="{\"providerGuid\":\"$SUPPLIER_ID\",\"providerCode\":\"SUP-TENDER-$SMOKE_SUFFIX\",\"providerName\":\"tender qualified supplier\",\"mainCategoryCode\":\"CAT-SMOKE\"}"
request supplier_create POST /api/company/source/srm/providers 201 "$supplier_body" "tender-supplier-create-$SMOKE_SUFFIX"
request supplier_check_sign GET "/api/company/srm/providers/$SUPPLIER_ID/check-sign" 200
/usr/bin/jq -e --arg id "$SUPPLIER_ID" \
  '.success == true and .decision == "derived_command_preview" and .data.providerGuid == $id and .data.allow == true and .data.requireExtraApprove == false and .data.sourceKind == "command" and .data.risk.rating == "C" and .persisted == false and .provider_execution == false and .authorizing == false' \
  "$TMP_DIR/supplier_check_sign.json" >/dev/null
request supplier_submit POST "/api/company/suppliers/$SUPPLIER_ID/submit_review" 200 '{}' "tender-supplier-submit-$SMOKE_SUFFIX"
request supplier_review POST "/api/company/suppliers/$SUPPLIER_ID/review" 200 '{"evaluation":"qualified","reason":"tender smoke qualification"}' "tender-supplier-review-$SMOKE_SUFFIX"

tender_body="{\"tender_id\":\"$TENDER_ID\",\"tender_code\":\"TD-CODE-$SMOKE_SUFFIX\",\"project_scope\":\"project:$PROJECT_ID\",\"name\":\"native tender smoke\",\"category\":\"construction\",\"estimated_amount_minor\":1234567,\"currency\":\"CNY\",\"bids\":[{\"supplier_id\":\"$SUPPLIER_ID\",\"amount_minor\":1200000}]}"
tender_key="tender-create-$SMOKE_SUFFIX"
request tender_create POST /api/company/tenders 201 "$tender_body" "$tender_key"
/usr/bin/jq -e --arg id "$TENDER_ID" '.tender.tender_id == $id and .tender.state == "planning"' "$TMP_DIR/tender_create.json" >/dev/null
request tender_replay POST /api/company/tenders 200 "$tender_body" "$tender_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/tender_replay.json" >/dev/null

request publish POST "/api/company/tenders/$TENDER_ID/publish" 200 '{}' "tender-publish-$SMOKE_SUFFIX"
request open_bidding POST "/api/company/tenders/$TENDER_ID/open_bidding" 200 '{}' "tender-open-$SMOKE_SUFFIX"
request award POST "/api/company/tenders/$TENDER_ID/award" 200 "{\"awarded_supplier_id\":\"$SUPPLIER_ID\",\"awarded_amount_minor\":1200000}" "tender-award-$SMOKE_SUFFIX"
request complete POST "/api/company/tenders/$TENDER_ID/complete" 200 '{}' "tender-complete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.tender.state == "completed"' "$TMP_DIR/complete.json" >/dev/null
request tender_read GET "/api/company/source/tender/tenders?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$TENDER_ID" 'any(.data[]; .tender_guid == $id and .source_kind == "command" and .state == "completed" and .estimated_amount_minor == 1234567)' "$TMP_DIR/tender_read.json" >/dev/null

split_body="{\"split_id\":\"$SPLIT_ID\",\"parent_contract_id\":\"ht-tj-001\",\"split_name\":\"native split smoke\",\"split_amount_minor\":123450,\"split_pct_bps\":1000,\"scope\":\"project:$PROJECT_ID\"}"
request split_create POST /api/company/tender-splits 201 "$split_body" "split-create-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg id "$SPLIT_ID" '.split.split_id == $id and .split.state == "planned"' "$TMP_DIR/split_create.json" >/dev/null
request split_replay POST /api/company/tender-splits 200 "$split_body" "split-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/split_replay.json" >/dev/null
request split_read GET '/api/company/source/tender/splits?parentContractGuid=ht-tj-001' 200
/usr/bin/jq -e --arg id "$SPLIT_ID" 'any(.data[]; .split_guid == $id and .source_kind == "command" and .split_amount_minor == 123450 and .split_pct_bps == 1000)' "$TMP_DIR/split_read.json" >/dev/null

source_tender_body="{\"tenderGuid\":\"$SOURCE_TENDER_ID\",\"projGuid\":\"$PROJECT_ID\",\"tenderName\":\"source tender smoke\",\"category\":\"construction\",\"estimatedAmount\":\"12345.67\",\"planPublishDate\":\"2026-07-14\",\"planAwardDate\":\"2026-08-01\",\"remark\":\"source tender alias smoke\",\"bids\":[{\"supplierId\":\"$SUPPLIER_ID\",\"amount_minor\":1200000}]}"
source_tender_key="source-tender-create-$SMOKE_SUFFIX"
request source_tender_create POST /api/company/source/tender/tenders 201 "$source_tender_body" "$source_tender_key"
/usr/bin/jq -e --arg id "$SOURCE_TENDER_ID" '.success == true and .data.tenderGuid == $id and .source_kind == "command"' "$TMP_DIR/source_tender_create.json" >/dev/null
request source_tender_replay POST /api/company/source/tender/tenders 200 "$source_tender_body" "$source_tender_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/source_tender_replay.json" >/dev/null
request source_tender_read GET "/api/company/source/tender/tenders?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$SOURCE_TENDER_ID" 'any(.data[]; .tender_guid == $id and .source_kind == "command" and .plan_publish_date == "2026-07-14" and .estimated_amount_minor == 1234567)' "$TMP_DIR/source_tender_read.json" >/dev/null
request source_state_publish PUT "/api/company/source/tender/tenders/$SOURCE_TENDER_ID/state" 200 '{"state":"publishing"}' "source-tender-publish-$SMOKE_SUFFIX"
request source_state_bidding PUT "/api/company/source/tender/tenders/$SOURCE_TENDER_ID/state" 200 '{"state":"bidding"}' "source-tender-bidding-$SMOKE_SUFFIX"
source_award_body="{\"tenderGuid\":\"$SOURCE_TENDER_ID\",\"providerGuid\":\"$SUPPLIER_ID\",\"providerName\":\"tender qualified supplier\",\"awardAmount\":\"12000.00\",\"awardDate\":\"2026-07-15\",\"remark\":\"source award alias smoke\"}"
request source_award POST /api/company/source/tender/awards 200 "$source_award_body" "source-tender-award-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg id "$SOURCE_TENDER_ID" '.success == true and .data.tenderGuid == $id and .data.providerGuid != "" and .data.awardAmount == 12000' "$TMP_DIR/source_award.json" >/dev/null
request source_award_read GET "/api/company/source/tender/awards?tenderGuid=$SOURCE_TENDER_ID" 200
/usr/bin/jq -e --arg id "$SOURCE_TENDER_ID" 'any(.data[]; .tender_guid == $id and .source_kind == "command" and .award_amount == 12000 and .state == "awarded")' "$TMP_DIR/source_award_read.json" >/dev/null
request source_tender_delete DELETE "/api/company/source/tender/tenders/$SOURCE_TENDER_ID" 200 '{"reason":"source tender tombstone smoke"}' "source-tender-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .tender.state == "deleted"' "$TMP_DIR/source_tender_delete.json" >/dev/null

source_split_body="{\"splitGuid\":\"$SOURCE_SPLIT_ID\",\"parentContractGuid\":\"ht-tj-001\",\"splitName\":\"source split smoke\",\"splitAmount\":\"1234.50\",\"splitPct\":\"10.00\",\"scope\":\"project:$PROJECT_ID\"}"
source_split_key="source-split-create-$SMOKE_SUFFIX"
request source_split_create POST /api/company/source/tender/splits 201 "$source_split_body" "$source_split_key"
/usr/bin/jq -e --arg id "$SOURCE_SPLIT_ID" '.success == true and .data.splitGuid == $id and .source_kind == "command"' "$TMP_DIR/source_split_create.json" >/dev/null
request source_split_replay POST /api/company/source/tender/splits 200 "$source_split_body" "$source_split_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/source_split_replay.json" >/dev/null
request source_split_read GET '/api/company/source/tender/splits?parentContractGuid=ht-tj-001' 200
/usr/bin/jq -e --arg id "$SOURCE_SPLIT_ID" 'any(.data[]; .split_guid == $id and .source_kind == "command" and .split_amount_minor == 123450 and .split_pct_bps == 1000)' "$TMP_DIR/source_split_read.json" >/dev/null

request tender_delete DELETE "/api/company/tenders/$TENDER_ID" 200 '{"reason":"tender tombstone smoke"}' "tender-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.tender.state == "deleted"' "$TMP_DIR/tender_delete.json" >/dev/null
request source_read_after GET "/api/company/source/tender/tenders?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$TENDER_ID" 'all(.data[]; .tender_guid != $id)' "$TMP_DIR/source_read_after.json" >/dev/null
request supplier_void DELETE "/api/company/source/srm/providers/$SUPPLIER_ID" 200 '{"reason":"tender smoke cleanup"}' "tender-supplier-void-$SMOKE_SUFFIX"

echo "native MoonBit tender/split lifecycle and source-alias smoke passed"
