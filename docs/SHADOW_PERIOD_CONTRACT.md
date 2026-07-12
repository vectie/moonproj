# Read-Only Shadow-Period Contract

Recorded: 2026-07-13  
Status: contract implemented; operations authorization pending

The migration must run beside the working ERP before any record-class
ownership transfer. `scripts/company_shadow_period_check.py` validates a
versioned shadow manifest and the current technical evidence.

The contract requires:

- the legacy ERP remains authoritative;
- target mode is `read_only_shadow`;
- target business mutations are disabled;
- bounded duration and comparison interval;
- explicit comparison dimensions for identity, projections, row coverage,
  money totals, accounting links, replay, and exceptions;
- a named operations owner and rollback runbook;
- all projection parity reports are `shadow_verified`;
- all available source rows have coverage;
- accounting reconciliation has no cash release or period posting.

The checked-in
`scripts/fixtures/shadow_period_manifest.example.json` defines a 14-day,
24-hour comparison period. The rehearsal emits `shadow-period.json` as
`shadow_pending_owner` until the business-acceptance packet's
`shadow-period` decision is explicitly `accept_for_shadow`. Even then,
`cutover_authorized` remains false.
