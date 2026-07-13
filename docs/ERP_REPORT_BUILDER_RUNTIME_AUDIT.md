# ERP report-builder runtime audit

Recorded: 2026-07-14

The source report builder has two read surfaces: a code-defined whitelist of
available tables/columns/operators and user/team saved templates. Running a
template is a separate SQL execution path; saving and deleting templates are
mutations.

## Connected reads

The PostgreSQL service and read-model adapter expose:

- `/api/company/reports/templates/meta`
- `/api/company/reports/templates`

The metadata response preserves the ten source table definitions and eight
operators without executing SQL. The template response preserves the source
template shape and reports `sys_report_template` coverage. The current export
has no saved-template rows, so Rabbita `/report-builder` shows empty-source
template state after successful reads while retaining the designer builder
layout and metadata table.

Both reads are non-authorizing and non-persisting. Template execution,
creation, deletion, CSV/PDF export, production identity, and report-owner
acceptance remain separate gates.
