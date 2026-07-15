#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4208}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-warning-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-warning-actor-secret}
RULE_ACTOR=${MOONPROJ_RULE_ACTOR_ID:-admin}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-warning.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
WARNING_GUID="source:W005:proj-0002"
COMMAND_KEY="warning-resolve-$SMOKE_SUFFIX"
EVENT_ID="warning:resolve:$COMMAND_KEY"
RULE_KEY="warning-rule-config-$SMOKE_SUFFIX"
RULE_EVENT_ID="warning:rule_config:$RULE_KEY"
CUSTOM_CODE="X999"
CUSTOM_KEY="warning-custom-create-$SMOKE_SUFFIX"
CUSTOM_DELETE_KEY="warning-custom-delete-$SMOKE_SUFFIX"
CUSTOM_EVENT_ID="warning:custom_rule_create:$CUSTOM_KEY"
CUSTOM_DELETE_EVENT_ID="warning:custom_rule_delete:$CUSTOM_DELETE_KEY"
TICKET_KEY="warning-ticket-create-$SMOKE_SUFFIX"
TICKET_EVENT_ID="warning:ticket_create:$TICKET_KEY"
TICKET_ID="local-ticket-$TICKET_KEY"
ASSIGNEE_ID="user-admin-0001"
NEW_ASSIGNEE_ID="user-lmj-0001"
NEW_ASSIGNEE_ACTOR="limingjin"
STATUS_HANDLING_KEY="warning-ticket-status-handling-$SMOKE_SUFFIX"
STATUS_HANDLING_EVENT_ID="warning:ticket_status:$STATUS_HANDLING_KEY"
STATUS_HANDLING_NEW_KEY="${STATUS_HANDLING_KEY}-new"
STATUS_HANDLING_NEW_EVENT_ID="warning:ticket_status:$STATUS_HANDLING_NEW_KEY"
STATUS_DONE_KEY="warning-ticket-status-done-$SMOKE_SUFFIX"
STATUS_DONE_EVENT_ID="warning:ticket_status:$STATUS_DONE_KEY"
REASSIGN_KEY="warning-ticket-reassign-$SMOKE_SUFFIX"
REASSIGN_EVENT_ID="warning:ticket_reassign:$REASSIGN_KEY"
EXTEND_KEY="warning-ticket-extend-$SMOKE_SUFFIX"
EXTEND_EVENT_ID="warning:ticket_extend:$EXTEND_KEY"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'warning_state' AND aggregate_id = '$WARNING_GUID') OR (aggregate_type = 'warning_rule_config' AND aggregate_id = 'W005') OR (aggregate_type = 'warning_custom_rule' AND aggregate_id = '$CUSTOM_CODE') OR (aggregate_type = 'warning_ticket' AND aggregate_id = '$TICKET_ID'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$COMMAND_KEY', 'moonproj:audit:$EVENT_ID', 'moonproj:command:$RULE_KEY', 'moonproj:audit:$RULE_EVENT_ID', 'moonproj:command:$CUSTOM_KEY', 'moonproj:audit:$CUSTOM_EVENT_ID', 'moonproj:command:$CUSTOM_DELETE_KEY', 'moonproj:audit:$CUSTOM_DELETE_EVENT_ID', 'moonproj:command:$TICKET_KEY', 'moonproj:audit:$TICKET_EVENT_ID', 'moonproj:command:$STATUS_HANDLING_KEY', 'moonproj:audit:$STATUS_HANDLING_EVENT_ID', 'moonproj:command:$STATUS_HANDLING_NEW_KEY', 'moonproj:audit:$STATUS_HANDLING_NEW_EVENT_ID', 'moonproj:command:$STATUS_DONE_KEY', 'moonproj:audit:$STATUS_DONE_EVENT_ID', 'moonproj:command:$REASSIGN_KEY', 'moonproj:audit:$REASSIGN_EVENT_ID', 'moonproj:command:$EXTEND_KEY', 'moonproj:audit:$EXTEND_EVENT_ID');" \
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

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
rule_signature=$(/usr/bin/printf '%s' "$RULE_ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
assignee_signature=$(/usr/bin/printf '%s' "$RULE_ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
new_assignee_signature=$(/usr/bin/printf '%s' "$NEW_ASSIGNEE_ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
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

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $TICKET_KEY" \
  --data "{\"assigneeUserId\":\"$ASSIGNEE_ID\",\"note\":\"native ticket smoke\",\"dueDate\":\"2030-01-01\"}" \
  "http://127.0.0.1:$PORT/api/company/warning/$WARNING_GUID/to-ticket")
test "$status" = 200
/usr/bin/jq -e '.warning.ticketId == "'"$TICKET_ID"'" and .warning.warningGuid == "'"$WARNING_GUID"'" and .warning.status == "open" and .warning.persisted == true and .warning.notificationSent == false and .warning.webhookSent == false and .warning.authorizing == false' "$TMP_DIR/ticket.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-replay.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $TICKET_KEY" \
  --data "{\"assigneeUserId\":\"$ASSIGNEE_ID\",\"note\":\"native ticket smoke\",\"dueDate\":\"2030-01-01\"}" \
  "http://127.0.0.1:$PORT/api/company/source/warning/$WARNING_GUID/to-ticket")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.ticketId == "'"$TICKET_ID"'"' "$TMP_DIR/ticket-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $assignee_signature" \
  "http://127.0.0.1:$PORT/api/company/source/warning/tickets/mine" >"$TMP_DIR/tickets.json"
/usr/bin/jq -e '.data | any(.[]; .ticketId == "'"$TICKET_ID"'" and .warningGuid == "'"$WARNING_GUID"'" and .commandProjection == true and .status == "open")' "$TMP_DIR/tickets.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-handling.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $assignee_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $STATUS_HANDLING_KEY" \
  --data '{"status":"handling","note":"started handling"}' \
  "http://127.0.0.1:$PORT/api/company/warning/tickets/$TICKET_ID/status")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .ticket.ticketId == "'"$TICKET_ID"'" and .ticket.status == "handling" and .ticket.transition == "status" and .ticket.notificationSent == false and .ticket.authorizing == false' "$TMP_DIR/ticket-handling.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-handling-replay.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $assignee_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $STATUS_HANDLING_KEY" \
  --data '{"status":"handling","note":"started handling"}' \
  "http://127.0.0.1:$PORT/api/company/source/warning/tickets/$TICKET_ID/status")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .ticket.status == "handling"' "$TMP_DIR/ticket-handling-replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-extend.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $assignee_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $EXTEND_KEY" \
  --data '{"newDueDate":"2030-02-01","reason":"native extension"}' \
  "http://127.0.0.1:$PORT/api/company/source/warning/tickets/$TICKET_ID/extend")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .ticket.ticketId == "'"$TICKET_ID"'" and .ticket.dueDate == "2030-02-01" and .ticket.transition == "extend" and .ticket.authorizing == false' "$TMP_DIR/ticket-extend.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-reassign.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $REASSIGN_KEY" \
  --data "{\"newAssigneeUserId\":\"$NEW_ASSIGNEE_ID\",\"reason\":\"native reassignment\"}" \
  "http://127.0.0.1:$PORT/api/company/source/warning/tickets/$TICKET_ID/reassign")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .ticket.assigneeUserId == "'"$NEW_ASSIGNEE_ID"'" and .ticket.status == "open" and .ticket.transition == "reassign" and .ticket.authorizing == false' "$TMP_DIR/ticket-reassign.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-new-assignee-handling.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $NEW_ASSIGNEE_ACTOR" -H "X-Moonproj-Actor-Signature: $new_assignee_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $STATUS_HANDLING_NEW_KEY" \
  --data '{"status":"handling"}' \
  "http://127.0.0.1:$PORT/api/company/warning/tickets/$TICKET_ID/status")
test "$status" = 200
/usr/bin/jq -e '.ticket.assigneeUserId == "'"$NEW_ASSIGNEE_ID"'" and .ticket.status == "handling"' "$TMP_DIR/ticket-new-assignee-handling.json" >/dev/null

body='{"note":"native warning smoke"}'
status=$(/usr/bin/curl -sS -o "$TMP_DIR/resolve.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $COMMAND_KEY" \
  --data "$body" \
  "http://127.0.0.1:$PORT/api/company/warning/$WARNING_GUID/resolve")
if [ "$status" != "200" ]; then
  /bin/cat "$TMP_DIR/resolve.json" "$TMP_DIR/service.log"
  exit 1
fi
/usr/bin/jq -e '.idempotent_replay == false and .warning.state == "resolved" and .warning.persisted == true and .warning.authorizing == false and .warning.cashEffect == false' "$TMP_DIR/resolve.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-done.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $NEW_ASSIGNEE_ACTOR" -H "X-Moonproj-Actor-Signature: $new_assignee_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $STATUS_DONE_KEY" \
  --data '{"status":"done","note":"completed from native smoke"}' \
  "http://127.0.0.1:$PORT/api/company/warning/tickets/$TICKET_ID/status")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .ticket.status == "done" and .ticket.warningResolved == true and .ticket.handledAt != null and .ticket.notificationSent == false and .ticket.webhookSent == false' "$TMP_DIR/ticket-done.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ticket-done-replay.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $NEW_ASSIGNEE_ACTOR" -H "X-Moonproj-Actor-Signature: $new_assignee_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $STATUS_DONE_KEY" \
  --data '{"status":"done","note":"completed from native smoke"}' \
  "http://127.0.0.1:$PORT/api/company/source/warning/tickets/$TICKET_ID/status")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .ticket.status == "done"' "$TMP_DIR/ticket-done-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $NEW_ASSIGNEE_ACTOR" -H "X-Moonproj-Actor-Signature: $new_assignee_signature" \
  "http://127.0.0.1:$PORT/api/company/source/warning/tickets/mine" >"$TMP_DIR/tickets-done.json"
/usr/bin/jq -e '.data | any(.[]; .ticketId == "'"$TICKET_ID"'" and .assigneeUserId == "'"$NEW_ASSIGNEE_ID"'" and .status == "done" and .handledAt != null and .handledNote == "completed from native smoke")' "$TMP_DIR/tickets-done.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/rule.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $RULE_KEY" \
  --data '{"enabled":false}' "http://127.0.0.1:$PORT/api/company/source/warning/rules/W005")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .warning.ruleCode == "W005" and .warning.enabled == false and .warning.authorizing == false and .warning.authorization_candidate == true' "$TMP_DIR/rule.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/rule-replay.json" -w '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $RULE_KEY" \
  --data '{"enabled":false}' "http://127.0.0.1:$PORT/api/company/warning/rules/W005")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.enabled == false' "$TMP_DIR/rule-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/warning/rules" >"$TMP_DIR/rules.json"
/usr/bin/jq -e '.data | any(.[]; .ruleCode == "W005" and .enabled == false and .commandProjection == true and .sourceKind == "command")' "$TMP_DIR/rules.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/scan-preview.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' --data '{}' \
  "http://127.0.0.1:$PORT/api/company/source/warning/scan")
test "$status" = 200
/usr/bin/jq -e '.data.dryRun == true and .data.rulesRun == 12 and .data.persisted == false and .data.providerExecution == false and .data.queryExecution == false and .data.notificationsSent == 0 and .authorizing == false' "$TMP_DIR/scan-preview.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-preview.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' --data '{"sqlTemplate":"SELECT 1"}' \
  "http://127.0.0.1:$PORT/api/company/source/warning/custom-rules/preview")
test "$status" = 200
/usr/bin/jq -e '.success == true and .data.rows == [] and .data.total == 0 and .data.queryExecution == false and .data.persisted == false and .authorizing == false and .source_kind == "warning_custom_rule_preview_candidate"' "$TMP_DIR/custom-preview.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-preview-invalid.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' --data '{"sqlTemplate":"DELETE FROM foo"}' \
  "http://127.0.0.1:$PORT/api/company/warning/custom-rules/preview")
test "$status" = 400

custom_body="{\"ruleCode\":\"$CUSTOM_CODE\",\"ruleName\":\"Smoke custom rule\",\"severity\":\"warning\",\"bizType\":\"project\",\"sqlTemplate\":\"SELECT 1\",\"enabled\":true}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-create.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $CUSTOM_KEY" \
  --data "$custom_body" "http://127.0.0.1:$PORT/api/company/warning/custom-rules")
test "$status" = 200
/usr/bin/jq -e '.warning.ruleCode == "'"$CUSTOM_CODE"'" and .warning.custom == true and .warning.sqlTemplateRedacted == true and .warning.query_execution == false and .warning.authorizing == false' "$TMP_DIR/custom-create.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-replay.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $CUSTOM_KEY" \
  --data "$custom_body" "http://127.0.0.1:$PORT/api/company/source/warning/custom-rules")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.ruleCode == "'"$CUSTOM_CODE"'"' "$TMP_DIR/custom-replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/source/warning/custom-rules" >"$TMP_DIR/custom-list.json"
/usr/bin/jq -e '.data | any(.[]; .ruleCode == "'"$CUSTOM_CODE"'" and .custom == true and .sqlTemplateRedacted == true and .commandProjection == true)' "$TMP_DIR/custom-list.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-delete.json" -w '%{http_code}' \
  -X DELETE -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $CUSTOM_DELETE_KEY" \
  "http://127.0.0.1:$PORT/api/company/source/warning/custom-rules/$CUSTOM_CODE")
test "$status" = 200
/usr/bin/jq -e '.warning.ruleCode == "'"$CUSTOM_CODE"'" and .warning.state == "deleted" and .warning.query_execution == false' "$TMP_DIR/custom-delete.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-invalid.json" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $RULE_ACTOR" -H "X-Moonproj-Actor-Signature: $rule_signature" \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: warning-custom-invalid' \
  --data '{"ruleCode":"X998","ruleName":"bad","severity":"warning","sqlTemplate":"UPDATE foo"}' \
  "http://127.0.0.1:$PORT/api/company/warning/custom-rules")
test "$status" = 400

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $COMMAND_KEY" \
  --data "$body" \
  "http://127.0.0.1:$PORT/api/company/warning/$WARNING_GUID/resolve")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.state == "resolved"' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/warning?status=all" >"$TMP_DIR/list.json"
/usr/bin/jq -e '.data.rows[0].status == "resolved" and .data.rows[0].commandProjection == true and .command_projection_count == 1 and .persisted == true' "$TMP_DIR/list.json" >/dev/null

echo "native MoonBit warning resolve/idempotency/readback smoke passed"
