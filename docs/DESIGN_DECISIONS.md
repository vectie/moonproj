# Conversation Decision Record

Recorded: 2026-07-13  
Purpose: preserve the decisions and reasoning that shaped the company-product
migration.

## 1. Diagnose the product gap

The current Moon Suite feels like a person's workspace: it is good at
knowledge, conversations, goals, agents, tools, execution, and evidence. That
is valuable, but it is not yet a company. A company must own resources, hold
rights, delegate authority, enter obligations, exchange goods and money,
account for economic events, finance itself, pay tax, report, and withstand
audit.

Decision: treat institutional identity and economic existence as first-class
product requirements, not as metadata attached to a personal workspace.

## 2. Make the company system a separate product

The company system should be independently operable and should own its data,
database, rules, UI/API boundary, authorization, workflows, audit trail, and
release lifecycle.

Decision: build one standalone company product in one repository first. It may
be Moon Suite-aware, but Moon Suite availability is never required for core
company operation or recovery.

## 3. Keep integration shallow at the beginning

The initial design should not entangle every Moon Suite sibling. Cross-product
coupling would make ownership unclear and make a sibling outage look like a
company outage.

Decision: use explicit, optional ports. MoonClaw can execute bounded agent
work; MoonBook, MoonChat, MoonFlow, Moontown, Moondesk, MoonGate, MoonStat, and
other siblings can provide optional projections, scheduling, or interaction.
None can directly mutate company records.

## 4. Absorb Moonfish selectively

Investment analysis is part of the company's economic life, unlike general
workspace convenience. Moonfish contains reusable market evidence,
deterministic indicators, validation, risk/safety, replay, and migration
evidence.

Decision: absorb those capabilities into native investment packages, while
preserving local mandates, approval, position ownership, valuation, accounting,
and risk controls. Do not keep a permanent runtime dependency on Moonfish.

## 5. Preserve the ERP's breadth

The supplied ERP is a working site system, not a prototype to replace with a
small accounting kernel. Its 75 table definitions, 338 HTTP handler
registrations across 30 route files, 97 frontend source files, 50+ business
pages, and cross-domain workflows establish the minimum breadth.

Decision: ERP capability parity is a replacement gate. Internal implementation
can proceed slice by slice, but the product cannot claim success while project,
investment, cost, procurement, contract, expense, sales, workflow, warning,
reporting, RBAC, and AI-assisted paths remain unaddressed.

## 6. Migrate by ownership, not by screen

A screen-for-screen rewrite would hide data ownership, state, accounting, and
rollback risks.

Decision: use capability-oriented strangler migration:

```text
legacy-owned
  -> target-shadow
  -> target-owned-with-legacy-read
  -> target-owned
  -> legacy-archived
```

There is one authoritative writer for each record class. Imports are
repeatable, schema-versioned, source-identifiable, manifest-controlled,
parity-measured, and reversible.

## 7. Current implementation interpretation

The repository is an executable translation scaffold, not a replacement claim.
It now proves institutional/authority and finance foundations, many ERP
workflow slices, Moonfish analytics seed, migration envelopes and manifests,
durable file recovery, aggregate projections, parity metrics, asset
depreciation, explicit opening receivable/payable source-to-journal links,
separate sales-to-receivable and invoice-to-receivable recognition boundaries,
acceptance-gated delivery recognition links, and accepted-progress cost
forecast linkage.
It also has 220 passing MoonBit tests, executable opening control-total checks,
a credential-safe deterministic ERP row-export boundary, an idempotent durable
SQLite migration rehearsal, a repeatable end-to-end rehearsal wrapper, a
fail-closed mapped-cohort promotion planner, and a native domain-promotion
command that applies the 19-item cohort while refusing quarantined plans; the
same boundary now promotes the 2-definition/12-step workflow cohort only with
explicit capability mappings, and the 2-project/2-cohort lifecycle slice with
explicit stage mappings, plus dependency-ordered task structures while source
task state remains quarantined where it conflicts with target invariants. The
same boundary now also promotes the reviewed investment-model version and its
26 source indexes without interpreting their formula/accounting semantics. The
same boundary also promotes explicitly mapped contract states, planned
milestones, and requested settlements, while cash release and accounting remain
separate events. It now also promotes five credential-free user identities
without importing credentials or legacy super-user privilege, plus two audit
records only with explicit target interpretations, and one opaque parameter
dictionary with five options plus the explicitly mapped three-row
`vys_proceeding` expense catalog as an opaque `expense_proceeding` dictionary.
The
task-state planner now proves clean replay for `proj-0002` and keeps the two
`proj-0001` dependency conflicts quarantined. The
native receipt can now be durably projected into SQLite with revision and
idempotent replay controls; this remains an adapter rehearsal, not production
database service integration. The
reopened cohort is also checked by an exact source/target projection-parity
gate before it can be considered shadow-verified. The
typed-cohort runner now applies eight separately versioned workflow, lifecycle,
task-structure, investment, payment, user, audit, and parameter receipts plus
the clean project-2 task-state receipt; 34 additional items pass exact parity
without collapsing their mapping histories. Project 1 task-state conflicts
remain quarantined. Proceeding manager, department, and cost-code metadata
remain source evidence rather than inferred expense or accounting state.
The remaining non-empty typed source rows are now preserved separately as 40
evidence-only projections, including task snapshots and lifecycle-instance
history; this keeps them queryable without converting source reports,
assignees, catalogs, or proceedings into company authority or state.
accounting-link gate now validates two explicitly reviewed, balanced commitment
journals plus one employee-advance opening journal and persists their
source/event/journal identities transactionally with idempotent replay. That
receipt is deliberately not a posting, cash release, or period-close decision.
Employee-loan offset rows are likewise a separate state-replay cohort: the
native importer mutates only a matched advance and leaves expense/cash
recognition to a separately reviewed accounting event.
Every rehearsal also emits a schema-scope artifact: the supplied ERP
initializer defines 75 tables, the available fixture contains 26, and 49
remain schema-only until later cohorts. This boundary is carried into the
cutover exceptions so successful fixture parity cannot be mistaken for full
ERP coverage.
The next gates are managed production SQL deployment, persistent cross-domain
accounting/subledger links, remaining typed-row reconciliation, ERP shadow
acceptance, and cutover rehearsal.
The optional CBS cost-link cohort now demonstrates explicit source-cost to
governed-subject translation and replay, while full CBS schema coverage and
budget consumption remain migration gates.
The optional workflow-assignment cohort likewise translates six assignee rows
as configuration only; identity, delegation, and decision-time authority stay
separate controls.
The local access directory now also supports exact-scope separation-of-duties
rules that reject incompatible role assignments before a grant can be issued;
effective-dated delegation and revocation are bounded locally, while legacy
role-table migration remains a later gate.
The live `jd_task_report` row can now be translated through an explicit
draft-only delivery-progress cohort. Its source operator/date/summary remain
provenance, while delivery acceptance, recognition, cost consumption, and
task-state mutation remain separate gates.
The finance boundary now also has explicit asset-disposal derecognition
journals and source links, a separate reviewed tax-filing lifecycle, and bank
statement import, cash-movement reconciliation, and non-posting
statement-to-ledger evidence. A credential-free production deployment
contract validates managed SQL, backup/restore, encryption, observability, and
named finance/operations/security approvals; it remains owner-review evidence,
not authorization to cut over.

For the normative product boundary, see
[PRODUCT_CHARTER.md](PRODUCT_CHARTER.md). For the implementation sequence, see
[MIGRATION_PLAN.md](MIGRATION_PLAN.md).

## 8. PostgreSQL is the company-product target

The ERP source and the company product have different database roles. The
working ERP may remain MySQL-backed while it is being read or exported, but
that does not make MySQL a Moonproj dependency or target.

Decision: remove MySQL from the Moonproj target boundary. PostgreSQL is the
only production target; SQLite is retained only as a deterministic rehearsal
adapter, and the PostgreSQL adapter owns the durable target catalog, JSONB raw
envelopes, conflict checks, migration receipt, and replay behavior. The ERP
MySQL probe/export path remains explicitly source-only.

## 9. Use Rabbita for the company frontend

The company product needs its own operational surface, but that surface must
not become a second domain implementation or a deep Moon Suite dependency.

Decision: use MoonBit Rabbita for the browser frontend, built through Warren,
with the UI consuming reviewed company projections and emitting bounded
commands. Its visual baseline is the designer-built ERP in
`../erp/erp_new/web`—the shell, login, menu hierarchy, and dashboard are
copied before introducing a new product-native design system. The current
clone is intentionally fixture-backed and read-only; live API/query/command
wiring follows the same authority boundary as the domain and PostgreSQL
adapters, and the remaining ERP views are migrated incrementally rather than
being silently replaced by generic screens.
