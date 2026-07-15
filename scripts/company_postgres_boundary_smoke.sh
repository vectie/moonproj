#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4264}
DATABASE=${DATABASE:-moonproj}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-boundary-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-boundary-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
SMOKE_SUFFIX=$(/bin/date +%s)-$$
PROJECT_CODE="BOUNDARY-PROJECT-$SMOKE_SUFFIX"
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-boundary.XXXXXX")
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
MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

ready=0
for _ in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" \
    >"$TMP_DIR/health.json" 2>/dev/null; then
    ready=1
    break
  fi
  /bin/sleep 1
done
test "$ready" = 1
/usr/bin/jq -e '.capabilities | index("import_batch_candidate") and index("sales_customer_command") and index("sales_subscription_command") and index("sales_mortgage_command") and index("sales_refund_command") and index("sales_customer_delete_candidate") and index("cbs_mutation_boundary_candidate")' "$TMP_DIR/health.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/project-template.csv" -D "$TMP_DIR/project-template.headers" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/import/project/template")
test "$status" = 200
/usr/bin/grep -F 'Content-Type: text/csv; charset=utf-8' "$TMP_DIR/project-template.headers" >/dev/null
/usr/bin/grep -F 'Content-Disposition: attachment; filename=project_template.csv' "$TMP_DIR/project-template.headers" >/dev/null
/usr/bin/printf '\357\273\277projCode,projName,projShortName,buCode,projStatus,beginDate\n' | /usr/bin/cmp -s - "$TMP_DIR/project-template.csv"

status=$(/usr/bin/curl -sS -o "$TMP_DIR/unsupported-template.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/import/unsupported/template")
test "$status" = 400
/usr/bin/jq -e '.code == 40001 and .message == "不支持的 bizType"' "$TMP_DIR/unsupported-template.json" >/dev/null

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/awk '{print $1}')

CUSTOMER_KEY="boundary-customer-$SMOKE_SUFFIX"
CUSTOMER_CODE="CUS-BOUNDARY-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/customer-create.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $CUSTOMER_KEY" \
  --data "{\"customerCode\":\"$CUSTOMER_CODE\",\"customerName\":\"Native Boundary Customer\",\"phone\":\"13800000000\",\"projGuid\":\"proj-0001\"}" \
  "http://127.0.0.1:$PORT/api/company/source/sales/customers")
test "$status" = 200
/usr/bin/jq -e --arg code "$CUSTOMER_CODE" '.success == true and .customer.customerCode == $code and .persisted == true and .idempotent_replay == false' "$TMP_DIR/customer-create.json" >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/customer-replay.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $CUSTOMER_KEY" \
  --data "{\"customerCode\":\"$CUSTOMER_CODE\",\"customerName\":\"Native Boundary Customer\",\"phone\":\"13800000000\",\"projGuid\":\"proj-0001\"}" \
  "http://127.0.0.1:$PORT/api/company/source/sales/customers")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .persisted == true' "$TMP_DIR/customer-replay.json" >/dev/null
CUSTOMER_ID=$(/usr/bin/jq -r '.customer.customerGuid' "$TMP_DIR/customer-create.json")
status=$(/usr/bin/curl -sS -o "$TMP_DIR/customer-update.json" -w '%{http_code}' -X PUT \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: customer-update-$SMOKE_SUFFIX" \
  --data '{"customerName":"Native Boundary Customer Updated"}' \
  "http://127.0.0.1:$PORT/api/company/source/sales/customers/$CUSTOMER_ID")
test "$status" = 200
/usr/bin/jq -e '.success == true and .persisted == true' "$TMP_DIR/customer-update.json" >/dev/null
/usr/bin/curl -fsS -G -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  --data-urlencode "keyword=$CUSTOMER_CODE" \
  "http://127.0.0.1:$PORT/api/company/source/sales/customers" \
  | /usr/bin/jq -e --arg id "$CUSTOMER_ID" '.data | any(.[]; .customer_guid == $id and .customer_name == "Native Boundary Customer Updated" and .source_kind == "command")' >/dev/null

SUBSCRIPTION_KEY="boundary-subscription-$SMOKE_SUFFIX"
SUBSCRIPTION_CODE="SUB-BOUNDARY-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/subscription-create.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $SUBSCRIPTION_KEY" \
  --data "{\"subCode\":\"$SUBSCRIPTION_CODE\",\"customerGuid\":\"$CUSTOMER_ID\",\"projGuid\":\"proj-0001\",\"buildingNo\":\"1\",\"unitNo\":\"101\",\"totalPrice\":123.45}" \
  "http://127.0.0.1:$PORT/api/company/source/sales/subscriptions")
test "$status" = 200
/usr/bin/jq -e --arg code "$SUBSCRIPTION_CODE" '.success == true and .subscription.subCode == $code and .subscription.state == "subscribed" and .persisted == true' "$TMP_DIR/subscription-create.json" >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/subscription-replay.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $SUBSCRIPTION_KEY" \
  --data "{\"subCode\":\"$SUBSCRIPTION_CODE\",\"customerGuid\":\"$CUSTOMER_ID\",\"projGuid\":\"proj-0001\",\"buildingNo\":\"1\",\"unitNo\":\"101\",\"totalPrice\":123.45}" \
  "http://127.0.0.1:$PORT/api/company/source/sales/subscriptions")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .persisted == true' "$TMP_DIR/subscription-replay.json" >/dev/null
SUBSCRIPTION_ID=$(/usr/bin/jq -r '.subscription.subGuid' "$TMP_DIR/subscription-create.json")
status=$(/usr/bin/curl -sS -o "$TMP_DIR/subscription-convert.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: subscription-convert-$SMOKE_SUFFIX" \
  --data '{"paymentType":"按揭","signedDate":"2026-07-16"}' \
  "http://127.0.0.1:$PORT/api/company/source/sales/subscriptions/$SUBSCRIPTION_ID/convert-to-contract")
test "$status" = 200
/usr/bin/jq -e '.success == true and .subscription.state == "converted" and .subscription.contract_pending == true and .subscription.contract_created == false and .subscription.revenue_created == false' "$TMP_DIR/subscription-convert.json" >/dev/null
/usr/bin/curl -fsS -G -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  --data-urlencode "keyword=$SUBSCRIPTION_CODE" \
  "http://127.0.0.1:$PORT/api/company/source/sales/subscriptions" \
  | /usr/bin/jq -e --arg id "$SUBSCRIPTION_ID" '.data | any(.[]; .sub_guid == $id and .state == "converted" and .source_kind == "command")' >/dev/null

MORTGAGE_KEY="boundary-mortgage-$SMOKE_SUFFIX"
MORTGAGE_CODE="MTG-BOUNDARY-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/mortgage-create.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $MORTGAGE_KEY" \
  --data "{\"mortgageCode\":\"$MORTGAGE_CODE\",\"scontractGuid\":\"SCT-BOUNDARY-$SMOKE_SUFFIX\",\"bankName\":\"Native Boundary Bank\",\"loanAmount\":100000}" \
  "http://127.0.0.1:$PORT/api/company/source/sales/mortgages")
test "$status" = 200
/usr/bin/jq -e --arg code "$MORTGAGE_CODE" '.success == true and .mortgage.mortgageCode == $code and .mortgage.state == "applying" and .persisted == true' "$TMP_DIR/mortgage-create.json" >/dev/null
MORTGAGE_ID=$(/usr/bin/jq -r '.mortgage.mortgageGuid' "$TMP_DIR/mortgage-create.json")
status=$(/usr/bin/curl -sS -o "$TMP_DIR/mortgage-approve.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: mortgage-approve-$SMOKE_SUFFIX" \
  --data '{}' "http://127.0.0.1:$PORT/api/company/source/sales/mortgages/$MORTGAGE_ID/approve")
test "$status" = 200
/usr/bin/jq -e '.success == true and .mortgage.state == "approved"' "$TMP_DIR/mortgage-approve.json" >/dev/null
status=$(/usr/bin/curl -sS -o "$TMP_DIR/mortgage-release.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: mortgage-release-$SMOKE_SUFFIX" \
  --data '{}' "http://127.0.0.1:$PORT/api/company/source/sales/mortgages/$MORTGAGE_ID/release")
test "$status" = 200
/usr/bin/jq -e '.success == true and .mortgage.state == "released" and .mortgage.revenue_pending == true and .mortgage.revenue_updated == false and .cash_effect == false' "$TMP_DIR/mortgage-release.json" >/dev/null
/usr/bin/curl -fsS -G -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  --data-urlencode "keyword=$MORTGAGE_CODE" \
  "http://127.0.0.1:$PORT/api/company/source/sales/mortgages" \
  | /usr/bin/jq -e --arg id "$MORTGAGE_ID" '.data | any(.[]; .mortgage_guid == $id and .state == "released" and .source_kind == "command")' >/dev/null

REFUND_KEY="boundary-refund-$SMOKE_SUFFIX"
REFUND_CODE="RF-BOUNDARY-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/refund-create.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $REFUND_KEY" \
  --data "{\"refundCode\":\"$REFUND_CODE\",\"scontractGuid\":\"SCT-BOUNDARY-$SMOKE_SUFFIX\",\"reason\":\"Native boundary smoke\",\"refundAmount\":12.5}" \
  "http://127.0.0.1:$PORT/api/company/source/sales/refunds")
test "$status" = 200
/usr/bin/jq -e --arg code "$REFUND_CODE" '.success == true and .refund.refundCode == $code and .refund.state == "applying" and .persisted == true' "$TMP_DIR/refund-create.json" >/dev/null
REFUND_ID=$(/usr/bin/jq -r '.refund.refundGuid' "$TMP_DIR/refund-create.json")
status=$(/usr/bin/curl -sS -o "$TMP_DIR/refund-approve.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: refund-approve-$SMOKE_SUFFIX" \
  --data '{}' "http://127.0.0.1:$PORT/api/company/source/sales/refunds/$REFUND_ID/approve")
test "$status" = 200
/usr/bin/jq -e '.success == true and .refund.state == "approved" and .refund.contract_pending == true and .refund.revenue_pending == true and .refund.contract_updated == false and .refund.revenue_updated == false' "$TMP_DIR/refund-approve.json" >/dev/null
/usr/bin/curl -fsS -G -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  --data-urlencode "keyword=$REFUND_CODE" \
  "http://127.0.0.1:$PORT/api/company/source/sales/refunds" \
  | /usr/bin/jq -e --arg id "$REFUND_ID" '.data | any(.[]; .refund_guid == $id and .state == "approved" and .source_kind == "command")' >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/import.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: boundary-import-$SMOKE_SUFFIX" \
  --data "{\"rows\":[{\"projCode\":\"$PROJECT_CODE\",\"projName\":\"Boundary Project\",\"buCode\":\"TJGS\",\"projStatus\":\"initiation\"}],\"dryRun\":false}" \
  "http://127.0.0.1:$PORT/api/company/import/project")
test "$status" = 200
/usr/bin/jq -e '.data.mode == "commit" and .data.rowsAccepted == 1 and .data.persisted == true and .idempotent_replay == false' "$TMP_DIR/import.json" >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/projects?keyword=$PROJECT_CODE" \
  | /usr/bin/jq -e --arg code "$PROJECT_CODE" '.command_projection == true and any(.items[]; .project_code == $code and .source_kind == "command")' >/dev/null

CONTRACT_CODE="BOUNDARY-CONTRACT-$SMOKE_SUFFIX"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/import-contract.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: boundary-import-contract-$SMOKE_SUFFIX" \
  --data "{\"rows\":[{\"contractCode\":\"$CONTRACT_CODE\",\"contractName\":\"Boundary Contract\",\"projCode\":\"$PROJECT_CODE\",\"buCode\":\"TJGS\",\"signDate\":\"2026-07-16\",\"htAmount\":1}],\"dryRun\":false}" \
  "http://127.0.0.1:$PORT/api/company/import/contract")
test "$status" = 200
/usr/bin/jq -e '.data.mode == "commit" and .data.rowsAccepted == 1 and .data.persisted == true and .idempotent_replay == false' "$TMP_DIR/import-contract.json" >/dev/null
/usr/bin/curl -fsS -G -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  --data-urlencode "keyword=$CONTRACT_CODE" \
  "http://127.0.0.1:$PORT/api/company/source/cost/contracts" \
  | /usr/bin/jq -e --arg code "$CONTRACT_CODE" 'any(.data[]; .contractCode == $code and .sourceKind == "command")' >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/customer.json" -w '%{http_code}' -X DELETE \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Idempotency-Key: boundary-customer-delete' \
  "http://127.0.0.1:$PORT/api/company/sales/customers/customer-boundary-1")
test "$status" = 409
/usr/bin/jq -e '.code == 48001 and .source_kind == "sales_customer_delete_candidate" and .data.deleted == false' "$TMP_DIR/customer.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/cbs.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: boundary-cbs-r0' \
  --data '{"contractGuid":"contract-boundary-1"}' \
  "http://127.0.0.1:$PORT/api/company/cbs/r0/resolve")
test "$status" = 409
/usr/bin/jq -e '.code == 45001 and .source_kind == "cbs_mutation_boundary_candidate" and .data.mutated == false' "$TMP_DIR/cbs.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/login.json" -w '%{http_code}' -X POST \
  -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' \
  --data '{"userCode":"admin","password":"not-used"}' \
  "http://127.0.0.1:$PORT/api/company/auth/login")
test "$status" = 409
/usr/bin/jq -e '.code == 41001 and .source_kind == "auth_lifecycle_candidate" and .data.sessionIssued == false' "$TMP_DIR/login.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/profile.json" -w '%{http_code}' -X PUT \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: boundary-profile-$SMOKE_SUFFIX" \
  --data '{"empName":"Native Boundary Profile"}' \
  "http://127.0.0.1:$PORT/api/company/auth/profile")
test "$status" = 200
/usr/bin/jq -e '.auth.empName == "Native Boundary Profile" and .auth.persisted == true and .idempotent_replay == false' "$TMP_DIR/profile.json" >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/auth/me?userCode=admin" \
  | /usr/bin/jq -e '.data.empName == "Native Boundary Profile" and .source_kind == "imported"' >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/logout.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H "Idempotency-Key: boundary-logout-$SMOKE_SUFFIX" \
  "http://127.0.0.1:$PORT/api/company/auth/logout")
test "$status" = 200
/usr/bin/jq -e '.auth.sessionRevoked == true and .auth.persisted == true and .idempotent_replay == false' "$TMP_DIR/logout.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL import/sales boundary smoke passed'
