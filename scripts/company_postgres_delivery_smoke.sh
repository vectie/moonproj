#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4246}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-delivery-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-delivery-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-delivery.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PROGRESS_ID="PR-MB-SMOKE-$SMOKE_SUFFIX"
OUTPUT_ID="OUT-MB-SMOKE-$SMOKE_SUFFIX"
REPORT_ID="REP-MB-SMOKE-$SMOKE_SUFFIX"
PROJECT_ID="proj-0001"

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
/usr/bin/jq -e '.capabilities | index("delivery_command") and index("delivery_read")' "$TMP_DIR/health.json" >/dev/null

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

request overview GET "/api/company/delivery/overview?project_id=$PROJECT_ID" 200
/usr/bin/jq -e '(.tasks | length) >= 1 and (.reports | length) >= 1 and .authorizing == false' "$TMP_DIR/overview.json" >/dev/null
request source_progress GET "/api/company/source/delivery/progress?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e '.authorizing == false and .persisted == false' "$TMP_DIR/source_progress.json" >/dev/null
request tasks GET "/api/company/delivery/tasks?project_id=$PROJECT_ID" 200
/usr/bin/jq -e '(.items | length) >= 1 and .persisted == false' "$TMP_DIR/tasks.json" >/dev/null
request summary GET "/api/company/delivery/plan-summary?project_id=$PROJECT_ID" 200
/usr/bin/jq -e '.total >= 1 and .authorizing == false' "$TMP_DIR/summary.json" >/dev/null

progress_body="{\"progress_id\":\"$PROGRESS_ID\",\"project_id\":\"$PROJECT_ID\",\"principal_id\":\"co-delivery-smoke\",\"project_scope\":\"project:$PROJECT_ID\",\"stage\":\"主体结构\",\"plan_pct\":70,\"completed_value_minor\":125000,\"currency\":\"CNY\",\"evidence_ids\":[\"smoke:progress:photo-001\"],\"remark\":\"native delivery smoke\"}"
progress_key="delivery-progress-create-$SMOKE_SUFFIX"
request progress_create POST /api/company/delivery/progress 201 "$progress_body" "$progress_key"
/usr/bin/jq -e --arg id "$PROGRESS_ID" '.progress.aggregate_id == $id and .progress.state == "draft" and .progress.delivery_effect == false' "$TMP_DIR/progress_create.json" >/dev/null
request progress_replay POST /api/company/delivery/progress 200 "$progress_body" "$progress_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/progress_replay.json" >/dev/null

request progress_report POST "/api/company/delivery/progress/$PROGRESS_ID/report" 200 '{"progress_pct":55,"actual_date":"2026-07-13","evidence_ids":["smoke:progress:report-001"],"remark":"现场复核"}' "delivery-progress-report-$SMOKE_SUFFIX"
request progress_accept POST "/api/company/delivery/progress/$PROGRESS_ID/accept" 200 '{"acceptance_id":"accept-smoke-001","acceptance_evidence_ids":["smoke:progress:accept-001"]}' "delivery-progress-accept-$SMOKE_SUFFIX"
request progress_read GET "/api/company/delivery/progress/$PROGRESS_ID" 200
/usr/bin/jq -e --arg id "$PROGRESS_ID" '.progress_id == $id and .state == "accepted" and .source_kind == "command"' "$TMP_DIR/progress_read.json" >/dev/null

output_body="{\"output_id\":\"$OUTPUT_ID\",\"output_code\":\"OUT-CODE-$SMOKE_SUFFIX\",\"project_id\":\"$PROJECT_ID\",\"contract_id\":\"ht-tj-001\",\"period\":\"2026-07\",\"output_amount\":\"125000\",\"evidence_ids\":[\"smoke:output:measure-001\"],\"remark\":\"native output smoke\"}"
output_key="delivery-output-create-$SMOKE_SUFFIX"
request output_create POST /api/company/delivery/outputs 201 "$output_body" "$output_key"
/usr/bin/jq -e --arg id "$OUTPUT_ID" '.output.aggregate_id == $id and .output.state == "reported"' "$TMP_DIR/output_create.json" >/dev/null
request output_confirm POST "/api/company/delivery/outputs/$OUTPUT_ID/confirm" 200 '{"confirm_amount":"125000","confirmed_at":"2026-07-13","evidence_ids":["smoke:output:accept-001"]}' "delivery-output-confirm-$SMOKE_SUFFIX"
request output_read GET "/api/company/delivery/outputs?project_id=$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$OUTPUT_ID" 'any(.items[]; .output_id == $id and .state == "confirmed" and .source_kind == "command")' "$TMP_DIR/output_read.json" >/dev/null

report_body="{\"report_id\":\"$REPORT_ID\",\"task_id\":\"task-003\",\"project_id\":\"$PROJECT_ID\",\"progress_pct\":70,\"report_date\":\"2026-07-13\",\"summary\":\"native task report smoke\",\"evidence_ids\":[\"smoke:task-report:001\"]}"
request task_report POST /api/company/delivery/tasks/task-003/report 201 "$report_body" "delivery-task-report-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg id "$REPORT_ID" '.task_report.aggregate_id == $id and .task_report.state == "observed"' "$TMP_DIR/task_report.json" >/dev/null
request reports_read GET "/api/company/delivery/task-reports?task_id=task-003" 200
/usr/bin/jq -e --arg id "$REPORT_ID" 'any(.items[]; .report_id == $id and .source_kind == "command")' "$TMP_DIR/reports_read.json" >/dev/null

request progress_delete DELETE "/api/company/delivery/progress/$PROGRESS_ID" 200 '{"reason":"native delivery tombstone smoke"}' "delivery-progress-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.progress.state == "deleted"' "$TMP_DIR/progress_delete.json" >/dev/null
request progress_after GET "/api/company/delivery/progress?project_id=$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$PROGRESS_ID" 'all(.items[]; .progress_id != $id)' "$TMP_DIR/progress_after.json" >/dev/null

echo "native MoonBit delivery source/read/command lifecycle smoke passed"
