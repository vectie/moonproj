#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4263}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-investment-actual-smoke-token}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-investment-actual.XXXXXX")
PID=""

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id LIKE 'investment-actual-smoke:%';" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id LIKE 'investment-actual-smoke:%';" >/dev/null 2>&1 || true

psql -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES
('legacy/raw/ep_project','actual-smoke-project',1,'{"proj_guid":"actual-smoke-project","proj_name":"Actual Smoke Project","bu_guid":"actual-smoke-bu"}'::jsonb,'investment-actual-smoke:project'),
('legacy/raw/tzsy_excel_import','actual-smoke-import',1,'{"import_guid":"actual-smoke-import","proj_guid":"actual-smoke-project","version_guid":"actual-smoke-version","created_at":"2026-07-15 10:00:00","status":"parsed"}'::jsonb,'investment-actual-smoke:import'),
('legacy/raw/tzsy_version','actual-smoke-version',1,'{"version_guid":"actual-smoke-version","proj_guid":"actual-smoke-project","version_name":"Actual Smoke Plan","is_current":true}'::jsonb,'investment-actual-smoke:version'),
('legacy/raw/tzsy_profit_table','actual-smoke-r10',1,'{"import_guid":"actual-smoke-import","row_idx":10,"col_key":"C","num_value":1000}'::jsonb,'investment-actual-smoke:r10'),
('legacy/raw/tzsy_profit_table','actual-smoke-r12',1,'{"import_guid":"actual-smoke-import","row_idx":12,"col_key":"C","num_value":200}'::jsonb,'investment-actual-smoke:r12'),
('legacy/raw/tzsy_profit_table','actual-smoke-r13',1,'{"import_guid":"actual-smoke-import","row_idx":13,"col_key":"C","num_value":300}'::jsonb,'investment-actual-smoke:r13'),
('legacy/raw/tzsy_profit_table','actual-smoke-r19',1,'{"import_guid":"actual-smoke-import","row_idx":19,"col_key":"C","num_value":400}'::jsonb,'investment-actual-smoke:r19'),
('legacy/raw/tzsy_profit_table','actual-smoke-r20',1,'{"import_guid":"actual-smoke-import","row_idx":20,"col_key":"C","num_value":500}'::jsonb,'investment-actual-smoke:r20'),
('legacy/raw/tzsy_profit_table','actual-smoke-r25',1,'{"import_guid":"actual-smoke-import","row_idx":25,"col_key":"C","num_value":100}'::jsonb,'investment-actual-smoke:r25'),
('legacy/raw/tzsy_profit_table','actual-smoke-r27',1,'{"import_guid":"actual-smoke-import","row_idx":27,"col_key":"C","num_value":50}'::jsonb,'investment-actual-smoke:r27'),
('legacy/raw/tzsy_profit_table','actual-smoke-r28',1,'{"import_guid":"actual-smoke-import","row_idx":28,"col_key":"C","num_value":50}'::jsonb,'investment-actual-smoke:r28'),
('legacy/raw/tzsy_profit_table','actual-smoke-r29',1,'{"import_guid":"actual-smoke-import","row_idx":29,"col_key":"C","num_value":1000}'::jsonb,'investment-actual-smoke:r29'),
('legacy/raw/tzsy_profit_table','actual-smoke-r30',1,'{"import_guid":"actual-smoke-import","row_idx":30,"col_key":"C","num_value":500}'::jsonb,'investment-actual-smoke:r30'),
('legacy/raw/tzsy_profit_table','actual-smoke-r32',1,'{"import_guid":"actual-smoke-import","row_idx":32,"col_key":"C","num_value":800}'::jsonb,'investment-actual-smoke:r32'),
('legacy/raw/sale_revenue','actual-smoke-revenue',1,'{"proj_guid":"actual-smoke-project","status":"received","customer_name":"Smoke Buyer","amount":1000000,"receive_date":"2026-07-01"}'::jsonb,'investment-actual-smoke:revenue'),
('legacy/raw/sale_revenue','actual-smoke-sale',1,'{"proj_guid":"actual-smoke-project","status":"signed","customer_name":"Smoke Buyer","amount":1000000,"receive_date":"2026-06-01"}'::jsonb,'investment-actual-smoke:sale'),
('legacy/raw/cb_contract','actual-smoke-contract',1,'{"contract_guid":"actual-smoke-contract","proj_guid":"actual-smoke-project","contract_name":"Smoke Works","ht_amount":3000000,"sum_alter_amount":100000}'::jsonb,'investment-actual-smoke:contract'),
('legacy/raw/cb_htfk_apply','actual-smoke-apply',1,'{"apply_guid":"actual-smoke-apply","proj_guid":"actual-smoke-project","contract_guid":"actual-smoke-contract","subject":"Smoke payment","apply_amount":500000,"pay_state":"完全支付"}'::jsonb,'investment-actual-smoke:apply'),
('legacy/raw/vcb_expense','actual-smoke-marketing',1,'{"expense_guid":"actual-smoke-marketing","bu_guid":"actual-smoke-bu","subject":"营销推广","pay_amount":100000,"pay_state":"已支付","expense_code":"SM-MKT"}'::jsonb,'investment-actual-smoke:marketing'),
('legacy/raw/vcb_expense','actual-smoke-admin',1,'{"expense_guid":"actual-smoke-admin","bu_guid":"actual-smoke-bu","subject":"办公管理","pay_amount":200000,"pay_state":"已支付","expense_code":"SM-ADM"}'::jsonb,'investment-actual-smoke:admin'),
('legacy/raw/vcb_loan_simple','actual-smoke-loan',1,'{"loan_id":"actual-smoke-loan","proj_guid":"actual-smoke-project","loan_code":"SM-LOAN","subject":"Smoke loan","loan_amount":2000000,"remain_amount":1000000}'::jsonb,'investment-actual-smoke:loan');
SQL

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} MOONPROJ_SERVICE_TOKEN="$TOKEN" PSQL_BIN="$PSQL_BIN" "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/actual-smoke-project/profit-actual" >"$TMP_DIR/actual.json"
/usr/bin/jq -e '
  .success == true and .simulation == true and .authorizing == false and
  .data.projGuid == "actual-smoke-project" and
  .data.values.R6.total == 100 and
  .data.values.R11.total == 50 and
  .data.values.R19.total == 10 and
  .data.values.R20.total == 20 and
  .data.values.R29.total == 200 and
  .data.values.R30.total == 100 and
  .data.operating.collectionRate.value == 50 and
  (.data.children.R6 | length) == 1
' "$TMP_DIR/actual.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL investment profit-actual smoke passed'
