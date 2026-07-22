#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4259}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-dashboard-smoke-token}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-dashboard.XXXXXX")
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
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
PSQL_BIN="$PSQL_BIN" \
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

request() {
  name=$1
  path=$2
  /usr/bin/curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' \
    "http://127.0.0.1:$PORT$path" >"$TMP_DIR/$name.json"
}

/usr/bin/jq -e '.capabilities | index("dashboard_read")' "$TMP_DIR/health.json" >/dev/null
request overview /api/company/dashboard/group/overview
request funnel /api/company/dashboard/group/funnel
request anomalies '/api/company/dashboard/group/top-anomalies?limit=2'
request kpi /api/company/dashboard/project/proj-0001/kpi
request project_anomalies /api/company/dashboard/project/proj-0001/anomalies
request v2 '/api/company/dashboard/v2/group?projGuid=proj-0001'
request v3 '/api/company/dashboard/v3/group?projGuid=proj-0001'
request v3_bu '/api/company/dashboard/v3/group?buGuid=bu-tjgs-0001'
request v3_group /api/company/dashboard/v3/group

/usr/bin/jq -e '
  .success == true and .data.projectCount == 2 and .data.contractCount == 2 and
  .data.paidAmount == 5640000 and .source_coverage.ep_project == 2 and
  .source_coverage.cb_cost == 7 and (.missing_source_tables | index("sale_revenue")) != null and
  .authorizing == false and .persisted == false
' "$TMP_DIR/overview.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 7 and .data[0].stageCode == "initiation" and
  .data[0].count == 2 and .authorizing == false
' "$TMP_DIR/funnel.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 2 and
  (.data[0].projGuid == "proj-0001" or .data[0].projGuid == "proj-0002") and
  .authorizing == false
' "$TMP_DIR/anomalies.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data.project.projGuid == "proj-0001" and
  .data.kpi.progress.totalNodes == 5 and .data.kpi.contract.count == 2 and
  .data.kpi.payment.paidTotal == 5640000 and .authorizing == false
' "$TMP_DIR/kpi.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 1 and .data[0].severity == "warning" and
  (.data[0].title | contains("成本超目标")) and
  (.missing_source_tables | index("sale_revenue")) != null
' "$TMP_DIR/project_anomalies.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data.scope.projGuid == "proj-0001" and
  .data.kpi.projectCount == 1 and .data.kpi.contractInProgressAmount == 25050000 and
  (.data.paymentTrend | length) > 0 and
  .data.stageDistribution[0].stage == "development" and
  .data.stageDistribution[0].count == 1 and .authorizing == false
' "$TMP_DIR/v2.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data.scope.projGuid == "proj-0001" and
  .data.kpi.customerCount == 0 and .data.kpi.totalExpense == 564 and
  (.data.tops | type) == "object" and .authorizing == false and .persisted == false
' "$TMP_DIR/v3.json" >/dev/null
/usr/bin/jq -e '
  .data.scope.buGuid == "bu-tjgs-0001" and .data.scope.level == "bu" and
  .data.kpi.totalExpense == 564 and .authorizing == false
' "$TMP_DIR/v3_bu.json" >/dev/null
/usr/bin/jq -e '
  .data.scope.level == "group" and .data.kpi.totalExpense == 564 and
  (.data.expenseByCity | length) == 2 and .authorizing == false
' "$TMP_DIR/v3_group.json" >/dev/null

echo "native MoonBit dashboard/cockpit read smoke passed"
