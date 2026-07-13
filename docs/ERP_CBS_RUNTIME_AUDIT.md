# ERP CBS runtime audit

The Rabbita CBS routes now use a source-compatible PostgreSQL read boundary.
The authenticated service and read-model adapter expose the read-only ERP CBS
family:

- `/api/company/cbs/r-master`
- `/api/company/cbs/dict` and `/dict/f-balance`
- `/api/company/cbs/versions` and `/versions/compare`
- `/api/company/cbs/r0/queue`
- `/api/company/cbs/approval-rules` and `/approval-rules/pick`
- `/api/company/cbs/changes`
- `/api/company/cbs/demo/contracts`

The reads preserve the ERP response concepts for R master data, project/version
selection, leaf dictionaries, F-balance, version comparison, R0 queue,
approval-rule selection, change applications, and source contract rows. Every
response carries `source_coverage`, `missing_or_empty_source_tables`,
`source_kind`, and `authorizing=false`. No CBS mutation, budget reservation,
contract approval, or R0 resolution is authorized by this boundary.

The controlled export contains two `cb_contract` rows, both without CBS
classification, and no `cb_r_master`, `cb_subject_dict`, `cb_plan_version`,
`cb_expense_split`, `vcb_expense`, `wf_approval_rule`, or `cb_change_apply`
rows. Therefore the dict/version/F-balance/approval/change reads return an
explicit empty or covered-not-found state, while R0 queue returns the two
unclassified source contracts. The Rabbita CBS pages display this provenance
and keep the designer snapshot only as a transport-failure fallback.

CBS writes, budget ownership, accounting posting, cash release, tax, browser
production identity, and owner acceptance remain separate migration gates.
