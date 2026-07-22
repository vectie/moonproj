#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4232}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-rbac-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-rbac-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-rbac.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
ROLE_CODE="moonproj-smoke-role-$SMOKE_SUFFIX"
DELETE_ROLE_CODE="moonproj-delete-role-$SMOKE_SUFFIX"
ROLE_KEY="rbac-role-$SMOKE_SUFFIX"
DELETE_ROLE_KEY="rbac-delete-role-$SMOKE_SUFFIX"
ASSIGN_KEY="rbac-assignment-$SMOKE_SUFFIX"
DELETE_KEY="rbac-role-delete-$SMOKE_SUFFIX"
USER_CREATE_KEY="rbac-user-create-$SMOKE_SUFFIX"
USER_UPDATE_KEY="rbac-user-update-$SMOKE_SUFFIX"
USER_TOGGLE_KEY="rbac-user-toggle-$SMOKE_SUFFIX"
USER_RESET_KEY="rbac-user-reset-$SMOKE_SUFFIX"
LOCAL_USER_ID="local-user-$USER_CREATE_KEY"
LOCAL_USER_CODE="moonproj-smoke-user-$SMOKE_SUFFIX"
USER_ID="user-admin-0001"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'rbac_role' AND aggregate_id IN ('$ROLE_CODE', '$DELETE_ROLE_CODE')) OR (aggregate_type = 'rbac_user_roles' AND aggregate_id = '$USER_ID') OR (aggregate_type = 'rbac_user' AND aggregate_id = '$LOCAL_USER_ID'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$ROLE_KEY', 'moonproj:command:$DELETE_ROLE_KEY', 'moonproj:command:$ASSIGN_KEY', 'moonproj:command:$DELETE_KEY', 'moonproj:command:$USER_CREATE_KEY', 'moonproj:command:$USER_UPDATE_KEY', 'moonproj:command:$USER_TOGGLE_KEY', 'moonproj:command:$USER_RESET_KEY', 'moonproj:audit:rbac:role_upsert:$ROLE_KEY', 'moonproj:audit:rbac:role_upsert:$DELETE_ROLE_KEY', 'moonproj:audit:rbac:user_roles:$ASSIGN_KEY', 'moonproj:audit:rbac:role_delete:$DELETE_KEY', 'moonproj:audit:rbac:user_create:$USER_CREATE_KEY', 'moonproj:audit:rbac:user_update:$USER_UPDATE_KEY', 'moonproj:audit:rbac:user_toggle:$USER_TOGGLE_KEY', 'moonproj:audit:rbac:user_reset_password:$USER_RESET_KEY');" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$PORT" \
  --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/sed 's/^.*= //')
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

role_body="{\"roleCode\":\"$ROLE_CODE\",\"roleName\":\"Moonproj Smoke\",\"description\":\"local candidate\",\"dataScope\":\"self\",\"permissions\":[\"dashboard:read\",\"project:read\"]}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/role.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $ROLE_KEY" \
  --data "$role_body" \
  "http://127.0.0.1:$PORT/api/company/rbac/roles")
test "$status" = 201
/usr/bin/jq -e '.idempotent_replay == false and .rbac.authorization_candidate == true and .rbac.authorizing == false and .rbac.security_effect == true and .rbac.provider_execution == false and .rbac.cash_effect == false and .rbac.accounting_effect == false and .rbac.tax_effect == false' "$TMP_DIR/role.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/role-replay.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $ROLE_KEY" \
  --data "$role_body" \
  "http://127.0.0.1:$PORT/api/company/rbac/roles")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .rbac.aggregate_id == "'$ROLE_CODE'"' "$TMP_DIR/role-replay.json" >/dev/null

assign_body="{\"roleCodes\":[\"$ROLE_CODE\"]}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/assignment.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $ASSIGN_KEY" \
  --data "$assign_body" \
  "http://127.0.0.1:$PORT/api/company/rbac/users/$USER_ID/roles")
test "$status" = 200
/usr/bin/jq -e '.rbac.authorization_candidate == true and (.rbac.role_codes | index("'$ROLE_CODE'")) != null' "$TMP_DIR/assignment.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/rbac/roles" >"$TMP_DIR/roles.json"
/usr/bin/jq -e '.command_projection == true and (.data | any(.[]; .roleCode == "'$ROLE_CODE'" and .sourceKind == "command" and .userCount == 1))' "$TMP_DIR/roles.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/rbac/roles/$ROLE_CODE" >"$TMP_DIR/role-detail.json"
/usr/bin/jq -e '.data.roleCode == "'$ROLE_CODE'" and .data.commandProjection == true' "$TMP_DIR/role-detail.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/rbac/users" >"$TMP_DIR/users.json"
/usr/bin/jq -e '.data | any(.[]; .userId == "'$USER_ID'" and (.roles | index("'$ROLE_CODE'")) != null and .rolesSourceStatus == "COMMAND_PROJECTION")' "$TMP_DIR/users.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/rbac/me?userCode=$ACTOR" >"$TMP_DIR/me.json"
/usr/bin/jq -e '.data.roles | index("'$ROLE_CODE'")' "$TMP_DIR/me.json" >/dev/null
/usr/bin/jq -e '(.data.permissions | index("dashboard:read")) != null and .authorization_candidate == true and .authorizing == false' "$TMP_DIR/me.json" >/dev/null

user_body="{\"userCode\":\"$LOCAL_USER_CODE\",\"empName\":\"Moonproj User\",\"password\":\"secret-not-returned\"}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/user-create.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $USER_CREATE_KEY" \
  --data "$user_body" "http://127.0.0.1:$PORT/api/company/rbac/users")
test "$status" = 201
/usr/bin/jq -e '.rbac.aggregate_id == "'"$LOCAL_USER_ID"'" and .rbac.credential_values_redacted == true and (.command.request.changes.password == null)' "$TMP_DIR/user-create.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/rbac/users" >"$TMP_DIR/users-with-local.json"
/usr/bin/jq -e --arg code "$LOCAL_USER_CODE" --arg id "$LOCAL_USER_ID" \
  '.data | any(.[]; .userCode == $code and .userId == $id and .sourceKind == "command" and .commandProjection == true)' \
  "$TMP_DIR/users-with-local.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/local-login.json" -w '%{http_code}' -X POST \
  -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' \
  --data "{\"user_code\":\"$LOCAL_USER_CODE\",\"password\":\"secret-not-returned\"}" \
  "http://127.0.0.1:$PORT/api/company/auth/login")
test "$status" = 200
/usr/bin/jq -e --arg code "$LOCAL_USER_CODE" \
  '.authenticated == true and .actor_id == $code and .identity_source == "postgresql_credential" and .credentialValuesRedacted == true' \
  "$TMP_DIR/local-login.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/user-update.json" -w '%{http_code}' \
  -X PUT -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $USER_UPDATE_KEY" \
  --data '{"empName":"Updated Admin"}' "http://127.0.0.1:$PORT/api/company/rbac/users/$USER_ID")
test "$status" = 200
/usr/bin/jq -e '.rbac.authorization_candidate == true and .rbac.authorizing == false' "$TMP_DIR/user-update.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/user-toggle.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $USER_TOGGLE_KEY" \
  --data '{}' "http://127.0.0.1:$PORT/api/company/rbac/users/$USER_ID/toggle")
test "$status" = 200
/usr/bin/jq -e '.rbac.security_effect == true and .rbac.authorizing == false' "$TMP_DIR/user-toggle.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/user-reset.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $USER_RESET_KEY" \
  --data '{"password":"reset-secret-not-returned"}' "http://127.0.0.1:$PORT/api/company/rbac/users/$USER_ID/reset-password")
test "$status" = 200
/usr/bin/jq -e '.rbac.credential_values_redacted == true and (.command.request.changes.password == null)' "$TMP_DIR/user-reset.json" >/dev/null

delete_body='{}'
delete_role_body="{\"roleCode\":\"$DELETE_ROLE_CODE\",\"roleName\":\"Delete Smoke\",\"permissions\":[]}"
/usr/bin/curl -fsS -o "$TMP_DIR/delete-create.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $DELETE_ROLE_KEY" \
  --data "$delete_role_body" "http://127.0.0.1:$PORT/api/company/rbac/roles" | /usr/bin/grep -q '^201$'
status=$(/usr/bin/curl -sS -o "$TMP_DIR/delete.json" -w '%{http_code}' \
  -X DELETE -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $DELETE_KEY" \
  --data "$delete_body" "http://127.0.0.1:$PORT/api/company/rbac/roles/$DELETE_ROLE_CODE")
test "$status" = 200
/usr/bin/jq -e '.rbac.state == "deleted" and .rbac.authorization_candidate == true' "$TMP_DIR/delete.json" >/dev/null

echo "native MoonBit RBAC role/user candidate/assignment/idempotency/readback smoke passed"
