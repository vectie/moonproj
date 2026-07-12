# Migration Completion Audit

Recorded: 2026-07-13  
Authoritative rehearsal: `/tmp/moonproj-rehearsal-export-request`

This is a completion audit, not a replacement claim. It distinguishes what is
verified in the repository from what still requires external source access or
named owner action.

## Verified

| Requirement | Evidence | Result |
|---|---|---|
| Standalone company product boundary | `PRODUCT_CHARTER.md`, `MOON_SUITE_BOUNDARY.md` | Complete; Moon Suite integrations are optional and shallow. |
| ERP breadth inventory | `ERP_CAPABILITY_BASELINE.md`, route/schema inventories | Complete; 75 schema tables, 30 route files, 338 handlers, 28 middleware registrations. |
| Available source preservation | `ERP_SNAPSHOT_INVENTORY.md`, raw staging, source export contract | Complete for the available artifact; 26 tables and 120 rows are hashed, redacted, and staged. |
| Row disposition coverage | `ERP_ROW_COVERAGE.md` | Complete for available rows; 120/120 covered, including aggregated parameter, investment, and workflow rows. |
| Schema-only translation | `ERP_SCHEMA_COHORTS.md` and seven cohort documents | Complete as semantic mapping; all 49 absent tables have owners/security controls, but no absent rows were fabricated. |
| Technical parity/replay | `cutover-gate.json` | Complete for supplied cohorts; parity, replay, backup/restore, SQL-driver, relationship, and accounting checks pass. |
| PostgreSQL target boundary | `POSTGRES_TARGET_SETUP.md`, `company_postgres_target_apply.py` | Complete for the available redacted cohort; PostgreSQL 18 catalog version 4 is applied, 120 raw envelopes are durable, and identical replay is idempotent. |
| Company browser surface | `frontend/main`, `frontend/public` | ERP-derived Rabbita shell/login/dashboard is complete and rendered in desktop and 390px mobile checks. Major ERP route families now render source-shaped read-only fixtures with the source tables, tabs, KPI cards, and action boundaries; detail/new routes and reviewed API/query/command boundaries remain open. |
| Domain and finance controls | implementation packages and 220 tests | Complete for implemented slices; accounting links remain traceability, not posting. |
| Business-acceptance packet | `BUSINESS_ACCEPTANCE_PACKET.md` | Contract complete; five decisions remain pending. |
| Shadow-period contract | `SHADOW_PERIOD_CONTRACT.md` | Contract complete; target is read-only and shadow authorization is pending. |

## Not verified / still open

| Requirement | Current evidence | Required next action |
|---|---|---|
| Complete production source export | `source-export-contract.json` is `source_export_incomplete` (26/75) | Supply the redacted MySQL/JSON export requested by `ERP_SOURCE_EXPORT_REQUEST.md`. |
| Live ERP availability | `ERP_MYSQL_SOURCE_PROBE.md` | Provision/reopen the configured MySQL listener or provide the export offline. |
| Production provider readiness | `production-deployment-gate.json` | Provision the managed database and obtain structured finance/operations/security approvals. |
| Business acceptance | `business-acceptance.json` | Named owners decide task-state, schema-scope, accounting, deployment, and shadow-period items. |
| Actual shadow operation | `shadow-period.json` is `shadow_pending_owner` | Run the agreed read-only comparison period and retain rollback evidence. |
| Ownership transfer/cutover | `cutover_authorized=false` | Only after source completeness, owner acceptance, shadow evidence, and rollback signoff. |

## Audit conclusion

The repository has a verified migration plan, translation map, technical
rehearsal, and controlled handoff. It is not yet a production migration because
the only available source is incomplete and the external owner/provider gates
are intentionally unresolved.
