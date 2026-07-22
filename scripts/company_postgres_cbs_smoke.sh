#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4254}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-cbs-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-cbs-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-cbs.XXXXXX")
PID=""

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id LIKE '%cbs-smoke%'; DELETE FROM company_aggregate_projection WHERE aggregate_id LIKE '%cbs-smoke%';" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

psql -v ON_ERROR_STOP=1 -c "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('legacy/raw/cb_plan_version','cbs-smoke-base',1,'{\"proj_guid\":\"proj-0001\",\"plan_version\":\"base-smoke\",\"version_name\":\"Base Smoke\",\"is_active\":true}'::jsonb,'cbs-smoke:base'),('legacy/raw/cb_subject_dict','cbs-smoke-dict',1,'{\"proj_guid\":\"proj-0001\",\"plan_version\":\"base-smoke\",\"dict_guid\":\"base-dict\",\"l3_code\":\"R1.01.01\",\"r_code\":\"R1\",\"l2_code\":\"R1.01\",\"l2_name\":\"Personnel\",\"subject\":\"Wages\",\"plan_amount\":100}'::jsonb,'cbs-smoke:dict')" >/dev/null

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required} PSQL_BIN="$PSQL_BIN" MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then break; fi
  /bin/sleep 1
done

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" -H 'Content-Type: application/json' "$@"
}

status=$(curl_common -sS -o "$TMP_DIR/clone.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: cbs-smoke-clone' --data '{"projGuid":"proj-0001","basePlanVersion":"base-smoke","newName":"CBS Smoke"}' "http://127.0.0.1:$PORT/api/company/cbs/versions/clone")
test "$status" = 201
/usr/bin/jq -e '.data.planVersion == "cbs-version-cbs-smoke-clone" and .data.cbs_effect == true and .data.authorizing == false' "$TMP_DIR/clone.json" >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/versions?projGuid=proj-0001" | /usr/bin/jq -e '.command_projection == true and (.data | any(.[]; .plan_version == "cbs-version-cbs-smoke-clone"))' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/dict?projGuid=proj-0001&planVersion=cbs-version-cbs-smoke-clone" | /usr/bin/jq -e '.data.items | any(.l3_code == "R1.01.01" and .src == "cloned")' >/dev/null
curl_common -fsS -X POST -H 'Idempotency-Key: cbs-smoke-dict' --data '{"projGuid":"proj-0001","planVersion":"cbs-version-cbs-smoke-clone","l2Code":"R1.01","subject":"Benefits","planAmount":25}' "http://127.0.0.1:$PORT/api/company/cbs/dict" | /usr/bin/jq -e '.data.l3Code == "R1.01.02" and .data.cbs_effect == true and .data.authorizing == false' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/dict?projGuid=proj-0001&planVersion=cbs-version-cbs-smoke-clone" | /usr/bin/jq -e '.data.items | any(.l3_code == "R1.01.02" and .subject == "Benefits" and .src == "manual")' >/dev/null
curl_common -fsS -X POST -H 'Idempotency-Key: cbs-smoke-adjust' --data '{"projGuid":"proj-0001","planVersion":"cbs-version-cbs-smoke-clone","rCode":"R1","pct":10}' "http://127.0.0.1:$PORT/api/company/cbs/dict/batch-adjust" | /usr/bin/jq -e '.data.affected == 2 and .data.factor == 1.1 and .data.cbs_effect == true and .data.budget_consumption == false and .authorizing == false' >/dev/null
curl_common -fsS -X POST -H 'Idempotency-Key: cbs-smoke-adjust' --data '{"projGuid":"proj-0001","planVersion":"cbs-version-cbs-smoke-clone","rCode":"R1","pct":10}' "http://127.0.0.1:$PORT/api/company/cbs/dict/batch-adjust" | /usr/bin/jq -e '.idempotent_replay == true and .data.affected == 2' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/cbs/dict?projGuid=proj-0001&planVersion=cbs-version-cbs-smoke-clone" | /usr/bin/jq -e '.data.items | any(.l3_code == "R1.01.01" and .plan_amount == 110) and any(.l3_code == "R1.01.02" and .plan_amount == 27.5)' >/dev/null
status=$(curl_common -sS -o "$TMP_DIR/imported-adjust.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: cbs-smoke-imported-adjust' --data '{"projGuid":"proj-0001","planVersion":"base-smoke","rCode":"R1","pct":10}' "http://127.0.0.1:$PORT/api/company/cbs/dict/batch-adjust")
test "$status" = 409
curl_common -fsS -X POST -H 'Idempotency-Key: cbs-smoke-freeze' --data '{"projGuid":"proj-0001","planVersion":"cbs-version-cbs-smoke-clone"}' "http://127.0.0.1:$PORT/api/company/cbs/versions/freeze" | /usr/bin/jq -e '.data.planVersion == "cbs-version-cbs-smoke-clone" and .data.cbs_effect == true' >/dev/null
curl_common -fsS -X POST -H 'Idempotency-Key: cbs-smoke-activate' --data '{"projGuid":"proj-0001","planVersion":"cbs-version-cbs-smoke-clone"}' "http://127.0.0.1:$PORT/api/company/cbs/versions/activate" | /usr/bin/jq -e '.data.planVersion == "cbs-version-cbs-smoke-clone" and .data.cbs_effect == true' >/dev/null
/usr/bin/printf '%s\n' 'native PostgreSQL CBS command smoke passed'
