#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4247}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-project-plan-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-project-plan-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-project-plan.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PROJECT_ID="proj-0001"
TASK_ID="PT-MB-SMOKE-$SMOKE_SUFFIX"

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
/usr/bin/jq -e '.capabilities | index("project_runtime_read") and index("project_plan_task_command") and index("plan_ai_suggestion_candidate")' "$TMP_DIR/health.json" >/dev/null

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

request projects GET /api/company/projects 200
/usr/bin/jq -e '(.items | length) == 2 and .source_kind == "imported" and .items[0].project_id != null' "$TMP_DIR/projects.json" >/dev/null
request project GET "/api/company/projects/$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$PROJECT_ID" '.project_id == $id and (.lifecycle | length) == 7 and .task_count >= 1' "$TMP_DIR/project.json" >/dev/null
request tasks GET "/api/company/projects/$PROJECT_ID/tasks" 200
/usr/bin/jq -e '(.items | map(select(.sourceKind == "imported")) | length) == 7 and .authorizing == false' "$TMP_DIR/tasks.json" >/dev/null
request lifecycle GET "/api/company/projects/$PROJECT_ID/lifecycle" 200
/usr/bin/jq -e '(.data.stages | length) == 7 and .authorizing == false' "$TMP_DIR/lifecycle.json" >/dev/null
request plan_summary GET "/api/company/projects/$PROJECT_ID/plan-summary" 200
/usr/bin/jq -e '.data.summary.total >= 1 and .authorizing == false' "$TMP_DIR/plan_summary.json" >/dev/null
request task_detail GET /api/company/tasks/task-003 200
/usr/bin/jq -e '.data.task.taskGuid == "task-003" and (.data.reports | length) >= 1' "$TMP_DIR/task_detail.json" >/dev/null
request delay_impact GET '/api/company/tasks/task-003/delay-impact?delayDays=3' 200
/usr/bin/jq -e '.data.source.delayDays == 3 and .data.calculation_available == true and .data.source.newEnd == "2026-12-18"' "$TMP_DIR/delay_impact.json" >/dev/null

ai_body='{"projType":"住宅","scale":"中型","region":"上海","beginDate":"2026-01-01"}'
request ai_suggest POST /api/company/plan/ai-suggest-plan 200 "$ai_body" "project-plan-ai-suggest-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and (.data.nodes | length) == 7 and .data.nodes[0].offsetDays == 0 and .data.nodes[6].planEndDate == "2027-01-01" and .data.provider == "native-deterministic" and .data.providerExecution == false and .persisted == false and .authorizing == false' "$TMP_DIR/ai_suggest.json" >/dev/null

task_body="{\"task_id\":\"$TASK_ID\",\"task_code\":\"PT-CODE-$SMOKE_SUFFIX\",\"task_name\":\"native project-plan smoke task\",\"project_id\":\"$PROJECT_ID\",\"task_type\":\"task\",\"plan_begin_date\":\"2026-08-01\",\"plan_end_date\":\"2026-08-15\",\"remarks\":\"native MoonBit smoke\",\"authority\":{\"active\":true,\"principal_id\":\"co-plan-smoke\",\"actor_id\":\"$ACTOR\",\"capability\":\"project:task:create\",\"scope\":\"project:$PROJECT_ID\"}}"
task_key="project-plan-create-$SMOKE_SUFFIX"
request task_create POST /api/company/plan/tasks 201 "$task_body" "$task_key"
/usr/bin/jq -e --arg id "$TASK_ID" '.task.taskGuid == $id and .task.state == "pending" and .task.cash_effect == false' "$TMP_DIR/task_create.json" >/dev/null
request task_replay POST /api/company/plan/tasks 200 "$task_body" "$task_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/task_replay.json" >/dev/null

update_body="{\"taskName\":\"native project-plan smoke task updated\",\"progressPct\":42,\"authority\":{\"active\":true,\"principal_id\":\"co-plan-smoke\",\"actor_id\":\"$ACTOR\",\"capability\":\"project:task:update\",\"scope\":\"project:$PROJECT_ID\"}}"
request task_update PUT "/api/company/plan/tasks/$TASK_ID" 200 "$update_body" "project-plan-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.task.state == "pending" and .task.cash_effect == false' "$TMP_DIR/task_update.json" >/dev/null
request tasks_after_create GET "/api/company/projects/$PROJECT_ID/tasks" 200
/usr/bin/jq -e --arg id "$TASK_ID" 'any(.items[]; .taskGuid == $id and .sourceKind == "command")' "$TMP_DIR/tasks_after_create.json" >/dev/null

report_body="{\"task_id\":\"$TASK_ID\",\"project_id\":\"$PROJECT_ID\",\"progress_pct\":42,\"report_date\":\"2026-07-15\",\"summary\":\"native local task report\",\"evidence_ids\":[\"smoke:plan-task:001\"]}"
request task_report POST "/api/company/plan/tasks/$TASK_ID/report" 201 "$report_body" "project-plan-report-$SMOKE_SUFFIX"
/usr/bin/jq -e '.task_report.state == "observed" and .task_report.cash_effect == false' "$TMP_DIR/task_report.json" >/dev/null
request task_detail_after_report GET "/api/company/tasks/$TASK_ID" 200
/usr/bin/jq -e --arg id "$TASK_ID" '.data.task.taskGuid == $id and (.data.reports | length) == 1' "$TMP_DIR/task_detail_after_report.json" >/dev/null

request task_delete DELETE "/api/company/plan/tasks/$TASK_ID" 200 '{"reason":"native project-plan tombstone smoke","authority":{"active":true,"principal_id":"co-plan-smoke","actor_id":"'"$ACTOR"'","capability":"project:task:delete","scope":"project:'"$PROJECT_ID"'"}}' "project-plan-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.task.state == "deleted" and .task.cash_effect == false' "$TMP_DIR/task_delete.json" >/dev/null
request tasks_after_delete GET "/api/company/projects/$PROJECT_ID/tasks" 200
/usr/bin/jq -e --arg id "$TASK_ID" 'all(.items[]; .taskGuid != $id)' "$TMP_DIR/tasks_after_delete.json" >/dev/null

echo "native MoonBit project-plan read/command lifecycle smoke passed"
