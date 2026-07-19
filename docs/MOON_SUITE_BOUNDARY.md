# Moon Suite Boundary and Reuse Map

Recorded: 2026-07-13  
Reference siblings: `/Users/kq/Workspace/moonbook`, `moonchat`, `moonclaw`,
`moondesk`, `moonfish`, `moonflow`, `moongate`, `moonlib`, `moonstat`,
`moontown`, and `moonrobo`

This is an ownership map for the standalone company product. It is based on
the sibling repositories' current README and package boundaries, not on a
shared runtime assumption. The company product must remain operable when all
of these siblings are absent.

Catalog refreshed: 2026-07-20 against the MoonBit product definitions in
`/Users/kq/Workspace/vectie.github.io/main/data_core.mbt` and
`main/data_more.mbt`. That public catalog describes MoonBook as knowledge,
MoonClaw as execution, MoonFlow as work progression, Moontown as standing
orchestration, MoonDesk as the human shell, and MoonGate as provider access and
telemetry. MoonProj remains the locally authoritative company product rather
than another shared workspace layer.

## The central distinction

Moon Suite products manage knowledge, conversation, agents, execution,
coordination, observation, and physical interfaces. The company product adds a
different kind of truth: an institution that owns resources, delegates legal
authority, incurs obligations, posts accounting entries, pays and collects,
finances itself, files tax, and controls investment capital.

The company product therefore consumes selected capabilities through explicit
ports, but it owns company records and business rules locally.

Awareness means MoonProj may publish or consume a versioned manifest, proposal,
receipt, evidence reference, or health observation. It does not mean shared
tables, shared filesystem state, required startup order, or permission for a
sibling to write company aggregates.

## Ownership map

| Sibling | Observed responsibility | Company-product relationship | Allowed initial boundary |
|---|---|---|---|
| MoonBook | Durable books, wiki pages, source material, accepted evidence, review queues, generated projections | Optional knowledge projection; never the company ledger or authoritative obligation store | Export/read approved evidence or research references through a versioned port |
| MoonChat | Conversation-shaped contracts and chat import/export; explicitly not agent execution or durable book truth | Optional interaction surface | Import a conversation reference or send a task/proposal; no direct mutation of company state |
| MoonClaw | Agent runtime, jobs, gateway, memory, artifacts, local/remote execution | Optional executor for bounded research, extraction, reconciliation assistance, and proposal preparation | Use `intelligence/agent_port`; every proposed mutation is re-authorized locally |
| MoonFlow | Declared-goal execution runtime, work graph, attempts, evidence, recovery, and adapter receipts | Optional execution orchestration for company-approved work | Accept typed receipts; never infer accounting, approval, or physical effects from completion alone |
| Moontown | Town-level scheduling, standing goals, cross-book routing, mayor supervision, and orchestration | Optional scheduler for recurring company observations or agent work | Receive proposals/receipts; company product controls authority, deadlines, and business effects |
| Moondesk | Human desktop shell for browsing books, reviewing artifacts, and submitting work | Optional UI; not a domain owner | Render company APIs or migration evidence without duplicating company rules in UI code |
| MoonGate | Local proxy/provider gateway, usage, pricing, quota, failover, and suite status | Optional model/provider connectivity and operational observation | Consume provider calls or health projections; no company data ownership |
| MoonStat | Observability, model/proxy status, usage and runtime metrics | Optional telemetry projection | Read metrics and provider readiness; never gate core accounting or settlement on it |
| MoonLib | Shared filesystem, path, clock, UUID, OS, and versioned cross-product DTO contracts | Reuse only dependency-light primitives where compatible | Keep imports narrow; do not import Moon Suite product policy into the company core |
| Moonfish | Market snapshots, deterministic indicators, validation, strategy routing, research routines, risk/safety, replay and cutover evidence | Absorb investment analytics and agent capability into native investment packages | Migrate evidence and deterministic algorithms; preserve mandate, approval, accounting, and risk authority locally |
| Moonrobo | Robot-facing gateway, safety, calibration, telemetry, physical controls, and RoboBook/MoonData links | Separate physical-domain product; future company asset/capex integration only | Integrate through asset, procurement, and evidence ports after the company model is ready |
| Moonmoon | Lunar terrain, mission, robot-data, and route-analysis product | Unrelated domain, not a company dependency | No integration in the initial product |

## Reuse rules

1. A sibling may provide an adapter, proposal, evidence, or receipt; it may not
   become the system of record for company identity, authority, money,
   obligations, journals, tax, or investment ownership.
2. Adapters are versioned and optional. Missing Moon Suite products must not
   prevent ordinary company operation, reporting, migration, or recovery.
3. Agent output is untrusted input. The company product rechecks principal,
   actor, capability, scope, amount, segregation of duties, workflow state,
   budget, accounting, tax, and idempotency before accepting a mutation.
4. Knowledge and evidence can be copied or referenced with provenance. A
   copied document, chat, or agent artifact does not become a legal or
   accounting fact until a company workflow accepts it.
5. Moonfish analytics may be reused as deterministic evidence, but an
   indicator or proposal never executes a trade, books a position, or changes a
   mandate without native investment controls.
6. UI and scheduler products observe or request; they do not bypass the
   company API to write database records.

## Integration order

The safest order is:

```text
basic OPC core
  -> evidence and proposal ports
  -> optional MoonClaw execution receipts
  -> Moonfish investment capability absorbed into native domain
  -> optional MoonBook/MoonFlow/Moondesk projections and receipts
  -> optional Moontown recurring coordination
  -> optional MoonGate/MoonStat telemetry
  -> vertical extension integration only when its own owner enables it
```

The first production release should require only the local basic OPC product.
The real-estate ERP is a separately enabled extension with its own parity and
cutover gates. All sibling lines improve automation or operator experience;
they do not define company-data ownership.

## Migration implications

- ERP rows and business events migrate into the company product's
  schema-versioned envelopes and aggregate projections.
- MoonBook/MoonClaw/Moonfish artifacts migrate as evidence, analytics inputs,
  proposal attachments, or replay references—not as uncontrolled writes.
- Moonfish decommission and rollback evidence remains archived after native
  investment parity is accepted.
- A sibling outage is an integration degradation, not a company ledger outage.
- A company cutover wave is complete only when the company product can operate,
  reconcile, back up, restore, and roll back without sibling availability.
