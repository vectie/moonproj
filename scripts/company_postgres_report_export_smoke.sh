#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4264}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-report-export-smoke-token}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-report-export.XXXXXX")
PID=""

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} \
  PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql} \
  MOONPROJ_SERVICE_TOKEN="$TOKEN" \
  "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1

body='{"filename":"native report / 2026","sheets":[{"name":"合同明细","columns":[{"label":"合同号","field":"code","width":18},{"label":"金额","field":"amount","type":"currency"},{"label":"比例","field":"ratio","type":"percent"},{"label":"日期","field":"date","type":"date"}],"rows":[{"code":"HT-001","amount":1234.5,"ratio":0.25,"date":"2026-07-15"},{"code":"中文","amount":99,"ratio":1,"date":"2026-07-16"}]},{"name":"摘要","columns":[{"label":"项目","field":"project"}],"rows":[{"project":"MoonSuite"}]}]}'
status=$(/usr/bin/curl -sS -D "$TMP_DIR/headers.txt" -o "$TMP_DIR/export.xlsx" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H 'Content-Type: application/json' -X POST --data "$body" \
  "http://127.0.0.1:$PORT/api/company/export/excel")
test "$status" = 200
/usr/bin/grep -qi '^Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' "$TMP_DIR/headers.txt"
/usr/bin/grep -qi '^Content-Disposition: attachment; filename="native report _ 2026.xlsx"' "$TMP_DIR/headers.txt"
/usr/bin/unzip -t "$TMP_DIR/export.xlsx" >/dev/null
/usr/bin/unzip -l "$TMP_DIR/export.xlsx" | /usr/bin/grep -q 'xl/worksheets/sheet1.xml'
/usr/bin/unzip -l "$TMP_DIR/export.xlsx" | /usr/bin/grep -q 'xl/worksheets/sheet2.xml'
/usr/bin/unzip -p "$TMP_DIR/export.xlsx" xl/workbook.xml | /usr/bin/grep -q '合同明细'
/usr/bin/unzip -p "$TMP_DIR/export.xlsx" xl/worksheets/sheet1.xml | /usr/bin/grep -q 'HT-001'
/usr/bin/unzip -p "$TMP_DIR/export.xlsx" xl/worksheets/sheet1.xml | /usr/bin/grep -q '1234.5'

status=$(/usr/bin/curl -sS -o "$TMP_DIR/invalid.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H 'Content-Type: application/json' -X POST --data '{"filename":"empty"}' \
  "http://127.0.0.1:$PORT/api/company/export/excel")
test "$status" = 422

/usr/bin/printf '%s\n' 'native PostgreSQL XLSX report export smoke passed'
