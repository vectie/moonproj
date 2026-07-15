# ERP report-builder runtime audit

Recorded: 2026-07-14

The source report builder has two read surfaces: a code-defined whitelist of
available tables/columns/operators and user/team saved templates. Running a
template is a separate SQL execution path; saving and deleting templates are
mutations.

## Connected reads

The native MoonBit PostgreSQL service and read-model adapter expose:

- `/api/company/reports/templates/meta`
- `/api/company/reports/templates`

The metadata response preserves the ten source table definitions and eight
operators without executing SQL. The template response preserves the source
template shape and reports `sys_report_template` coverage. The current export
has no saved-template rows, so Rabbita `/report-builder` shows empty-source
template state after successful reads while retaining the designer builder
layout and metadata table.

Both reads are non-authorizing and non-persisting. Template execution,
creation, and deletion now have a bounded local command boundary in
`cmd/postgres_company_service/report_commands.mbt`. Commands persist only
`report_template` aggregate revisions, idempotency receipts, and audit events;
imported `sys_report_template` rows remain read-only. Template execution
validates the same table/column/operator whitelist and evaluates imported JSON
envelopes in memory with `sql_executed=false`; it never accepts raw SQL,
invokes a provider, changes budget/accounting/cash/tax state, or persists
report results. The pure-shell PostgreSQL smoke covers create, replay, run,
delete, and tombstone readback. Native `POST /api/company/export/excel` accepts
the source-shaped `filename`/`sheets`/`columns`/`rows` contract and emits a
valid multi-sheet XLSX with a pure MoonBit ZIP/XML writer. It enforces 20
sheets, one million cells, and 32KB cell limits, sanitizes workbook/sheet
names, preserves text/numeric values and basic styles, and has no SQL,
provider, cash, accounting, or tax effect. The export smoke validates headers,
ZIP integrity, workbook parts, Unicode/text/numeric content, and empty-sheet
rejection. PDF export, production identity, managed serving, browser
acceptance, and report-owner acceptance remain separate gates.

Command paths:

- `POST /api/company/reports/templates`
- `POST /api/company/reports/templates/run`
- `DELETE /api/company/reports/templates/:id`
- `POST /api/company/export/excel`
