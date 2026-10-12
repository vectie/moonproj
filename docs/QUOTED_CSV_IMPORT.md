# Quoted project and contract CSV intake

The existing **Projects** and **Contracts** CSV picker now accepts quoted CSV
values, including commas, doubled quotes, and line breaks within a field. It
uses the same five-row preview, signed service dry-run, and explicit batch
commit workflow. This is a local intake feature, not a new import endpoint.

## Use the existing picker

1. Download the project or contract CSV template on its existing page. Keep
   its field names; reorder columns if needed.
2. Fill the file as UTF-8 CSV. A BOM is supported. Quote values containing a
   comma, newline, or quote; represent a literal quote as two quotes.
3. Select the file. Inspect the first five decoded rows and total row count.
   The preview and request use the same complete parsed batch.
4. Resolve any parser error by editing the indicated physical line/column or
   header, then select the corrected file. No partial batch remains ready.
5. Run the existing server dry-run. Resolve service validation failures, then
   use the existing explicit commit control only after a successful dry-run.

For example, a project name with a comma and literal quotes is preserved:

```csv
projCode,projName,projShortName,buCode,projStatus,beginDate
P-1,"Planning, ""phase one""",Phase one,BU-1,initiation,2026-10-11
```

Quoted multiline values are one logical record. CRLF and CR line endings
normalize to LF inside fields. Leading/trailing field whitespace is trimmed,
matching the previous picker; interior whitespace is preserved. Blank physical
lines are ignored. A quoted empty cell is a cell, and trailing empty cells must
still have their delimiters. Spaces/tabs after a closing quote are allowed;
spaces before an opening quote are not part of this CSV dialect.

## Repairable errors and bounds

The picker rejects duplicate, empty, or malformed headers, unequal record
widths, unclosed/misplaced quotes, trailing text after a closing quote, and NUL
characters. It no longer silently truncates extra cells, fills missing cells,
or overwrites duplicate columns. Headers use the template's ASCII field-name
syntax (letter followed by letters, digits, or underscores; at most 64
characters).

The local parser allows at most 500 data records, 64 columns, 32,768 UTF-16 code
units per field, and 2 Mi UTF-16 code units per decoded file. The file-size bound
applies after the existing FileReader reads the selected file; it is not a
streaming or pre-read memory guarantee. These parser limits do not assert that
the service will accept a row.

## Authority and compatibility

Native service templates and routes are unchanged. Parser success checks CSV
structure only. It does not check actor permissions, business-unit/project
existence, duplicate business codes, dates, or amounts. The native service
remains responsible for those checks, idempotency, canonical identity, and
transactional persistence. In particular, the contract service also needs an
explicit business-unit reference: add a `buCode` column (or its supported
`buGuid` reference) when preparing the existing contract template. The picker
does not infer that reference from a project or company context.

Amount text stays text until native validation; the parser never rounds or
converts money. A successful parse is not an import, customer acceptance,
accounting posting, cash movement, or cutover authorization. The authoritative
ERP and existing signed command boundaries remain unchanged.

## Reproduce the focused tests

From the repository root:

```sh
node --test scripts/test_import_csv.mjs
```

The suite extracts and executes the production JS extern, including an actual
UTF-8 Blob passed through the production file-reading callback with simulated
FileReader/document objects. It checks both native template header strings,
quoted/multiline/Unicode data, malformed input, bounds, ordinary legacy input,
and generated round trips. Source assertions check the MoonBit adapter and
reducer wiring. This qualifies only the extracted JS parser and simulated
file-callback behavior. It does not qualify a compiled MoonBit/Rabbita build,
a real browser, PostgreSQL dry-run/commit, production identity, or providers.

See [ERP import runtime audit](ERP_IMPORT_RUNTIME_AUDIT.md) for the existing
signed service workflow and remaining acceptance gates. The feature supports
MoonProj PRD MOONPROJ-UC04/B04's operator input workflow while retaining the
MOONPROJ-N01 authority separation. It does not change PRD acceptance status.
