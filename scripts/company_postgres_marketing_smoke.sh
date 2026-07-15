#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4244}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-marketing-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-marketing-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-marketing.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
CAMPAIGN_ID="CAMP-MB-SMOKE-$SMOKE_SUFFIX"
PLACEMENT_ID="PLAC-MB-SMOKE-$SMOKE_SUFFIX"
CHANNEL_ID="CH-MB-SMOKE-$SMOKE_SUFFIX"
MATERIAL_ID="MAT-MB-SMOKE-$SMOKE_SUFFIX"
PRINCIPAL="co-marketing-smoke"
SCOPE="project:CD-HJL"

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
/usr/bin/jq -e '.capabilities | index("marketing_command") and index("marketing_observation_read")' "$TMP_DIR/health.json" >/dev/null

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

campaign_body="{\"campaignGuid\":\"$CAMPAIGN_ID\",\"campaignCode\":\"CAMP-CODE-$SMOKE_SUFFIX\",\"projGuid\":\"CD-HJL\",\"name\":\"native marketing campaign\",\"campaignType\":\"推广活动\",\"budget\":\"123.45\",\"startDate\":\"2026-07-15\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:campaign:create\",\"max_amount_minor\":20000}}"
campaign_key="marketing-campaign-create-$SMOKE_SUFFIX"
request campaign_create POST /api/company/marketing/campaigns 201 "$campaign_body" "$campaign_key"
/usr/bin/jq -e --arg id "$CAMPAIGN_ID" '.campaign.aggregate_id == $id and .campaign.state == "planning"' "$TMP_DIR/campaign_create.json" >/dev/null
request campaign_replay POST /api/company/marketing/campaigns 200 "$campaign_body" "$campaign_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/campaign_replay.json" >/dev/null

campaign_update_body="{\"name\":\"updated marketing campaign\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:campaign:update\",\"max_amount_minor\":0}}"
request campaign_update PUT "/api/company/marketing/campaigns/$CAMPAIGN_ID" 200 "$campaign_update_body" "marketing-campaign-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.campaign.state == "planning"' "$TMP_DIR/campaign_update.json" >/dev/null

channel_body="{\"channelGuid\":\"$CHANNEL_ID\",\"channelCode\":\"CH-CODE-$SMOKE_SUFFIX\",\"name\":\"native channel\",\"channelType\":\"线上\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:channel:create\",\"max_amount_minor\":0}}"
request channel_create POST /api/company/marketing/channels 201 "$channel_body" "marketing-channel-create-$SMOKE_SUFFIX"

placement_body="{\"placementGuid\":\"$PLACEMENT_ID\",\"placementCode\":\"PLAC-CODE-$SMOKE_SUFFIX\",\"campaignGuid\":\"$CAMPAIGN_ID\",\"channelGuid\":\"$CHANNEL_ID\",\"channelName\":\"native channel\",\"amount\":\"12.34\",\"placeDate\":\"2026-07-15\",\"durationDays\":30,\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:placement:create\",\"max_amount_minor\":2000}}"
request placement_create POST /api/company/marketing/placements 201 "$placement_body" "marketing-placement-create-$SMOKE_SUFFIX"

effect_body="{\"impressions\":1000,\"clicks\":50,\"leads\":5,\"state\":\"completed\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:placement:effect\",\"max_amount_minor\":0}}"
request placement_effect PUT "/api/company/marketing/placements/$PLACEMENT_ID/effect" 200 "$effect_body" "marketing-placement-effect-$SMOKE_SUFFIX"

material_body="{\"materialGuid\":\"$MATERIAL_ID\",\"materialCode\":\"MAT-CODE-$SMOKE_SUFFIX\",\"projGuid\":\"CD-HJL\",\"name\":\"native material\",\"unitCost\":\"3.00\",\"quantity\":4,\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:material:create\",\"max_amount_minor\":2000}}"
request material_create POST /api/company/marketing/materials 201 "$material_body" "marketing-material-create-$SMOKE_SUFFIX"

request campaigns GET '/api/company/marketing/campaigns?projGuid=CD-HJL' 200
/usr/bin/jq -e --arg id "$CAMPAIGN_ID" 'any(.data[]; .campaignGuid == $id and .sourceKind == "command" and .name == "updated marketing campaign" and .budget == 123.45)' "$TMP_DIR/campaigns.json" >/dev/null
request placements GET "/api/company/marketing/placements?campaignGuid=$CAMPAIGN_ID" 200
/usr/bin/jq -e --arg id "$PLACEMENT_ID" 'any(.data[]; .placementGuid == $id and .sourceKind == "command" and .amount == 12.34 and .impressions == 1000 and .state == "completed")' "$TMP_DIR/placements.json" >/dev/null
request channels GET /api/company/marketing/channels 200
/usr/bin/jq -e --arg id "$CHANNEL_ID" 'any(.data[]; .channelGuid == $id and .sourceKind == "command" and .placementCount == 1 and .totalCost == 12.34)' "$TMP_DIR/channels.json" >/dev/null
request materials GET '/api/company/marketing/materials?projGuid=CD-HJL' 200
/usr/bin/jq -e --arg id "$MATERIAL_ID" 'any(.data[]; .materialGuid == $id and .sourceKind == "command" and .unitCost == 3 and .quantity == 4 and .totalCost == 12)' "$TMP_DIR/materials.json" >/dev/null
/usr/bin/jq -e '.source_coverage.mkt_campaign == 0 and .source_coverage.mkt_placement == 0 and .source_coverage.mkt_channel == 0 and .source_coverage.mkt_material == 0 and .authorizing == false and .persisted == false' "$TMP_DIR/campaigns.json" >/dev/null

delete_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:material:delete\",\"max_amount_minor\":0}}"
request material_delete DELETE "/api/company/marketing/materials/$MATERIAL_ID" 200 "$delete_body" "marketing-material-delete-$SMOKE_SUFFIX"
delete_channel_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:channel:delete\",\"max_amount_minor\":0}}"
request channel_delete DELETE "/api/company/marketing/channels/$CHANNEL_ID" 200 "$delete_channel_body" "marketing-channel-delete-$SMOKE_SUFFIX"
delete_campaign_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"marketing:campaign:delete\",\"max_amount_minor\":0}}"
request campaign_delete DELETE "/api/company/marketing/campaigns/$CAMPAIGN_ID" 200 "$delete_campaign_body" "marketing-campaign-delete-$SMOKE_SUFFIX"

echo "native MoonBit marketing source/command lifecycle smoke passed"
