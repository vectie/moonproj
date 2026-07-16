#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_ROOT=${1:?usage: company_cross_domain_projection_parity.sh WORK_DIR SQLITE_DATABASE OUTPUT [--host host --port port --user user --database database]}
SQLITE_DATABASE=${2:?usage: company_cross_domain_projection_parity.sh WORK_DIR SQLITE_DATABASE OUTPUT [options]}
OUTPUT=${3:?usage: company_cross_domain_projection_parity.sh WORK_DIR SQLITE_DATABASE OUTPUT [options]}
shift 3
WORK_DIR=${TMPDIR:-/tmp}/moonproj-cross-domain.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

receipt_count=0
for receipt in $(find "$WORK_ROOT" -type f -name '*.json' -print | sort); do
  if ! jq -e '(.format == "moonproj.erp.domain-promotion.v1")' "$receipt" >/dev/null 2>&1; then
    continue
  fi
  receipt_count=$((receipt_count + 1))
  sqlite_report="$WORK_DIR/sqlite-$receipt_count.json"
  postgres_report="$WORK_DIR/postgres-$receipt_count.json"
  sqlite_ok=0
  postgres_ok=0
  if "$SCRIPT_DIR/company_sqlite_exact_projection_parity.sh" "$receipt" "$SQLITE_DATABASE" "$sqlite_report" >/dev/null 2>&1; then sqlite_ok=1; fi
  if "$SCRIPT_DIR/company_postgres_exact_projection_parity.sh" "$receipt" "$postgres_report" "$@" >/dev/null 2>&1; then postgres_ok=1; fi
  if [ ! -s "$sqlite_report" ] || [ ! -s "$postgres_report" ]; then
    jq -n --arg file "$receipt" '{file:$file,state:"mismatch",expected_items:0,sqlite_items:0,postgres_items:0,duplicate_expected:[],sqlite_missing:[],postgres_missing:[],sqlite_extra:[],postgres_extra:[],cross_domain_missing:[],cross_domain_extra:[],payload_mismatches:[{key:["adapter-error"],sqlite_payload_count:0,postgres_payload_count:0}]}' >> "$WORK_DIR/cohorts.ndjson"
    continue
  fi
  jq -n --arg file "$receipt" --slurpfile sqlite "$sqlite_report" --slurpfile postgres "$postgres_report" --argjson sqlite_ok "$sqlite_ok" --argjson postgres_ok "$postgres_ok" '
    ($sqlite[0]) as $s | ($postgres[0]) as $p |
    (($s.candidate_mismatches + $p.candidate_mismatches | map(.key) | unique) as $keys |
      {file:$file,
       source_snapshot_id:$s.source_snapshot_id,
       mapping_version:$s.mapping_version,
       state:(if $sqlite_ok == 1 and $postgres_ok == 1 and $s.state == "shadow_verified" and $p.state == "shadow_verified" then "shadow_verified" else "mismatch" end),
       expected_items:$s.expected_items,
       sqlite_items:$s.actual_items,
       postgres_items:$p.actual_items,
       duplicate_expected:[],
       sqlite_missing:$s.missing,
       postgres_missing:$p.missing,
       sqlite_extra:$s.extra,
       postgres_extra:$p.extra,
       cross_domain_missing:[],
       cross_domain_extra:[],
       payload_mismatches:($keys | map(. as $key | {key:$key,sqlite_payload_count:(($s.candidate_mismatches | map(select(.key == $key) | .actual | length) | add) // 0),postgres_payload_count:(($p.candidate_mismatches | map(select(.key == $key) | .actual | length) | add) // 0)}))})' >> "$WORK_DIR/cohorts.ndjson"
done

if [ "$receipt_count" -eq 0 ]; then
  echo "company cross-domain projection parity failed: no domain promotion receipts found below $WORK_ROOT" >&2
  exit 1
fi
jq -s --arg sqlite "$SQLITE_DATABASE" --arg postgres "${PGDATABASE:-moonproj}" '
  {format:"moonproj.erp.cross-domain-projection-parity.v1",
   state:(if length > 0 and all(.[]; .state == "shadow_verified") then "shadow_verified" else "mismatch" end),
   sqlite_database:$sqlite, postgres_database:$postgres, receipt_count:length,
   verified_receipts:([.[] | select(.state == "shadow_verified")] | length), cohorts:.}' \
  "$WORK_DIR/cohorts.ndjson" > "$OUTPUT"
jq '{output:($output // ""),receipt_count:.receipt_count,verified_receipts:.verified_receipts,state:.state}' --arg output "$OUTPUT" "$OUTPUT"
state=$(jq -r '.state' "$OUTPUT")
[ "$state" = shadow_verified ]
