# Kimi OPC redesign audit

Date: 2026-07-21

Source reviewed:

- `~/Downloads/Kimi_Agent_MoonProj/MoonProj重构方案_OPC公司操作系统.md`
- `~/Downloads/Kimi_Agent_MoonProj/app/src`

## Product decision

MoonProj is a company operating system for one Owner and a bounded Agent fleet. It is not a personal workspace and its primary information architecture is no longer an ERP module directory. The Owner's scarce attention is the top-level organizing constraint.

The base product remains industry-neutral. Moon Suite awareness is an optional product-line mode. MoonClaw may supply Agent runtime capabilities. Moonfish is absorbed only as an investment-analysis Agent and cannot create trades or accounting facts without MoonProj authority and evidence. The real-estate ERP remains an explicit extension pack.

## Diagnostic-to-implementation matrix

| Reference finding | MoonProj response | Surface |
|---|---|---|
| Human hierarchy modeled instead of one Owner + Agents | Agent is a first-class operating actor with role, L0-L4 autonomy, budget and evidence | Agent fleet |
| Software and hardware lifecycles absent | Unified stage model with software release and EVT/DVT/PVT hardware paths | Project portfolio |
| 60+ module tables consume Owner attention | Navigation is grouped by command, execution, delivery, assurance and governance | Shell and cockpit |
| Approval workflow exists but product exit criteria do not | Seven Gates, three veto redlines and S/A/B/C exit grades | Factory quality |
| Owner must search for decisions | Attention queue is the cockpit's primary content; incomplete evidence physically disables adjudication | Cockpit |
| Agent activity lacks an operational overview | Four-column dispatch board separates autonomous execution from Owner acceptance | Dispatch |
| Monitoring does not control release pace | SLO and error-budget state are explicit; exhausted budgets freeze release | Observe |
| Incidents do not improve automation safely | Incident, postmortem and Runbook lifecycle blocks automation until learning closes | Operate |
| ERP breadth risks disappearing in an OPC redesign | Company domain compresses identity, rights, market, sales, procurement, contracts, expenses, finance, tax, capital, risk and continuity into one Owner-facing hub; detailed legacy domain views remain available | Company domain |
| Moon-specific dependencies could contaminate the base | Moon mode is optional and off by default; its registry is a projection | Mode switch and Moon project page |

## Navigation contract

| Group | Page | Owner question |
|---|---|---|
| Command | Cockpit | What must I decide today? |
| Execute | Agent fleet | What is my digital workforce doing? |
| Execute | Dispatch | What is running and what awaits my acceptance? |
| Deliver | Project portfolio | Which stage and Gate is each initiative at? |
| Deliver | Moon project | How far is each Moon product from exit? |
| Deliver | Factory quality | What evidence permits this product to ship? |
| Assure | Observe | Are SLOs and error budgets healthy? |
| Assure | Operate | Did we recover and learn from incidents? |
| Govern | Company domain | Can the company act, exchange, account and survive? |
| Govern | Evidence and audit | Who did what under which authority and with what result? |

## UI system adopted from the reference

- Dark, dense control-plane canvas with restrained violet primary semantics.
- Unified semantic colors: green healthy/released, amber risk/decision, red blocked/redline, violet Gate/product, blue Agent/information.
- Tabular numerals for money, ratios, versions and operational counts.
- Compact cards, inset panels, grouped sidebar navigation and a universal/Moon mode switch.
- Responsive board collapse at tablet and mobile widths.
- Buttons represent explicit state or intent. Evidence-deficient adjudication remains disabled.

## Data and authority boundary

The current redesign contains clearly modeled operating fixtures so all information architecture and interactions can be evaluated before live connectors exist. A UI action records only session intent. It does not claim a PostgreSQL write, bank movement, contract signature, deployment approval or accounting post. Existing fail-closed lifecycle helpers remain the authority boundary for detailed company workflows.

## Next production connectors

1. Project and Moon registry: GitHub repository, CI, test, coverage and environment evidence.
2. Observe: SLO and alert sources with calculated error budgets.
3. Agent fleet: MoonClaw status, budget usage and evidence receipts.
4. Company domain: existing PostgreSQL company services and projections.
5. Gate decisions: append-only evidence and explicit Owner authorization records.
