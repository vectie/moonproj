#!/bin/sh
set -eu

# Turn an already credential-safe snapshot export into raw migration
# envelopes. This script intentionally accepts the export directory rather
# than a SQLite database: it cannot read or persist password hashes, network
# addresses, or other source secrets by construction.

EXPORT_DIR=${1:-/tmp/moonproj-erp-export}
OUT_PATH=${2:-/tmp/moonproj-erp-staging.ndjson}
EXPORT_MANIFEST="$EXPORT_DIR/manifest.json"

if [ ! -f "$EXPORT_MANIFEST" ]; then
  echo "snapshot export manifest not found: $EXPORT_MANIFEST" >&2
  echo "run scripts/erp_snapshot_export.sh first" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

mkdir -p "$(dirname "$OUT_PATH")"
: > "$OUT_PATH"
ENTRIES="$OUT_PATH.entries"
: > "$ENTRIES"

SOURCE_HASH=$(jq -r '.source_sha256' "$EXPORT_MANIFEST")
if [ -z "$SOURCE_HASH" ] || [ "$SOURCE_HASH" = "null" ]; then
  echo "export manifest has no source hash" >&2
  exit 1
fi

tables=$(jq -r '.tables[] | [.table, .file, (.rows | tostring), .primary_key] | @tsv' \
  "$EXPORT_MANIFEST")
while IFS='	' read -r table relative rows primary_key; do
  [ -n "$table" ] || continue
  case "$relative" in
    tables/*.json) ;;
    *) echo "unsafe export path: $relative" >&2; exit 1 ;;
  esac
  table_path="$EXPORT_DIR/$relative"
  if [ ! -f "$table_path" ]; then
    echo "export table missing: $table_path" >&2
    exit 1
  fi

  # The exporter redacts these keys. Fail closed if a caller supplies an
  # untrusted or manually modified export instead of silently copying it.
  secret_count=$(jq '[.[] | keys[] | select(test("password|secret|token|private|ip$"; "i"))] | length' "$table_path")
  if [ "$secret_count" -ne 0 ]; then
    echo "secret-shaped key found in export table: $table" >&2
    exit 1
  fi

  if [ "$rows" -gt 0 ] && [ -z "$primary_key" ]; then
    echo "export manifest has no primary key for non-empty table: $table" >&2
    exit 1
  fi

  if [ "$rows" -gt 0 ]; then
    jq -c --arg table "$table" --arg pk "$primary_key" '
      .[]
      | . as $row
      | ($row[$pk] // error("missing primary key value")) as $id
      | ($id | tostring) as $text_id
      | {
          record_type: ("legacy/raw/" + $table),
          record_id: $text_id,
          source_id: ("erp:" + $table + ":" + $text_id),
          payload: $row
        }
    ' "$table_path" >> "$OUT_PATH"
  fi

  entry=$(jq -cn --arg table "$table" --arg pk "$primary_key" --argjson rows "$rows" \
    '{table:$table,primary_key:$pk,rows:$rows}')
  printf '%s\n' "$entry" >> "$ENTRIES"
done <<EOF
$tables
EOF

OUTPUT_HASH=$(hash_file "$OUT_PATH")
jq -s \
  --arg format "moonproj.erp.raw-staging.v1" \
  --arg export_manifest "$EXPORT_MANIFEST" \
  --arg source_sha256 "$SOURCE_HASH" \
  --arg output_path "$OUT_PATH" \
  --arg output_sha256 "$OUTPUT_HASH" \
  --arg redaction "input was an export with password, secret, token, private, and ip keys removed" \
  '{format:$format,export_manifest:$export_manifest,source_sha256:$source_sha256,output_path:$output_path,output_sha256:$output_sha256,redaction:$redaction,tables:.}' \
  "$ENTRIES" > "$OUT_PATH.manifest.json"
rm -f "$ENTRIES"
jq empty "$OUT_PATH.manifest.json"
echo "staging=$OUT_PATH"
echo "manifest=$OUT_PATH.manifest.json"
echo "source_sha256=$SOURCE_HASH"
echo "staged_rows=$(wc -l < "$OUT_PATH" | tr -d ' ')"
