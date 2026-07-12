# ERP Capability Baseline

Status: initial parity catalog  
Reference system: `../erp/erp_new`  
Recorded: 2026-07-13

## Purpose

The current ERP is an operating production reference, not disposable prototype
material. This catalog defines the minimum breadth the new product must preserve
before it can replace that ERP at the site.

At the time of inspection, the reference contained:

- 75 `CREATE TABLE IF NOT EXISTS` definitions in
  `server/src/db/index.js` (the available SQLite backup contains 26 of them);
- 338 `r.get/post/put/patch/delete` HTTP handler registrations across 30 route
  files (plus 28 router middleware registrations);
- 97 frontend source files and more than 50 business pages;
- project, investment, cost, contract, expense, sales, procurement, workflow,
  warning, reporting, RBAC, and AI capabilities.

Counts help size the system but are not acceptance criteria. Parity is measured
through business outcomes, state transitions, controls, reports, and reconciled
data.

## Parity levels

Each capability receives one of these states in the migration register:

| State | Meaning |
|---|---|
| `unmapped` | Existing behavior has not been analyzed. |
| `specified` | Actors, states, rules, data, and reports are documented. |
| `implemented` | New behavior exists but has not been compared with production. |
| `scenario-verified` | Repeatable parity scenarios pass. |
| `data-reconciled` | Representative migrated data reconciles. |
| `shadow-verified` | Production-like shadow runs match expected outcomes. |
| `cutover-ready` | Security, operations, user acceptance, and rollback gates pass. |
| `accepted` | Capability is live and the legacy path is read-only or retired. |

## Minimum functional baseline

### FND — Foundation and administration

| ID | Capability | Minimum outcome |
|---|---|---|
| FND-01 | Legal entity and business-unit hierarchy | Maintain group, company, department, project, and effective hierarchy. |
| FND-02 | Users and employment identity | Maintain users, employee identity, status, and organizational assignment. |
| FND-03 | Roles and permissions | Assign roles, permissions, data scope, and super-user controls. |
| FND-04 | Dictionaries and parameters | Effective configuration without source changes. |
| FND-05 | Attachments | Upload, classify, authorize, retain, and link evidence. |
| FND-06 | Audit and error records | Trace material reads, writes, approvals, failures, and administrative actions. |
| FND-07 | Notifications | Inbox, email, webhook, subscription, and digest behavior. |
| FND-08 | Health and administration | Operational health, configuration diagnostics, and controlled administration. |

### WF — Workflow and control

| ID | Capability | Minimum outcome |
|---|---|---|
| WF-01 | Process definitions | Configure processes, steps, assignees, thresholds, and applicability. |
| WF-02 | Approval execution | Start, approve, reject, withdraw, and inspect processes. |
| WF-03 | Weighted approval | Preserve threshold and weighted-assignee behavior. |
| WF-04 | Delegation and scope | Apply organizational, amount, project, and time limits. |
| WF-05 | SLA and warnings | Remind, escalate, and record overdue approval work. |
| WF-06 | Process visibility | Preview, trace current state, and inspect initiation and approval history. |
| WF-07 | Segregation of duties | Prevent incompatible preparation, approval, release, and reconciliation roles. |

### PRJ — Project and delivery

| ID | Capability | Minimum outcome |
|---|---|---|
| PRJ-01 | Project master and lifecycle | Create projects and manage lifecycle stages and organizational ownership. |
| PRJ-02 | Project plan | Plan tasks, milestones, dates, dependencies, and owners. |
| PRJ-03 | Progress | Record physical and value progress with evidence. |
| PRJ-04 | Delay impact | Project downstream schedule and economic effects. |
| PRJ-05 | Delivery acceptance | Record deliverables, inspection, acceptance, rejection, and remediation. |
| PRJ-06 | Project cockpit | Drill from group to company to project status and exceptions. |

### INV — Investment

| ID | Capability | Minimum outcome |
|---|---|---|
| INV-01 | Investment projects and versions | Maintain assumptions and controlled scenario versions. |
| INV-02 | Model import | Import and map spreadsheet models with preview, confidence, and audit. |
| INV-03 | Revenue, cost, tax, and financing plan | Represent the full project economic model. |
| INV-04 | IRR, NPV, margin, and sensitivity | Calculate deterministic metrics and compare scenarios. |
| INV-05 | Plan versus actual | Reconcile investment plans with operational performance. |
| INV-06 | Proposal and approval | Produce an evidence-backed investment case under a mandate. |
| INV-07 | Portfolio and position view | Aggregate approved investments, exposure, valuation, and performance. |
| INV-08 | Investment agents | Use absorbed Moonfish analytics and agents without bypassing approval. |

### CST — Budget, CBS, and cost

| ID | Capability | Minimum outcome |
|---|---|---|
| CST-01 | CBS master and versions | Govern cost subjects, versions, classifications, and R/R0 handling. |
| CST-02 | Target and responsibility cost | Establish approved baselines and responsible units. |
| CST-03 | Budget reservation and consumption | Reserve, consume, release, transfer, and prevent unauthorized overrun. |
| CST-04 | Dynamic cost | Reconcile planned, committed, forecast, actual, and remaining cost. |
| CST-05 | Multidimensional allocation | Allocate by entity, project, department, subject, activity, and party. |
| CST-06 | Cost cockpit | Drill into variance, commitment, forecast, and exceptions. |
| CST-07 | Progress-to-cost linkage | Feed accepted project progress into cost and forecast behavior. |

### SRM — Supplier, sourcing, and procurement

| ID | Capability | Minimum outcome |
|---|---|---|
| SRM-01 | Supplier master | Maintain qualification, categories, contacts, status, and ownership. |
| SRM-02 | Supplier risk | Score risk, concentration, blacklist, performance, and signing eligibility. |
| SRM-03 | Inquiry and quotation | Request, receive, normalize, and compare quotations. |
| SRM-04 | Tendering | Plan tenders, record bids, evaluate, approve awards, and retain evidence. |
| SRM-05 | Award-to-contract | Create controlled draft commitments from approved awards. |
| SRM-06 | Supplier performance | Connect delivery, quality, delay, invoice, and payment behavior. |

### CTR — Contract, commitment, payable, and payment

| ID | Capability | Minimum outcome |
|---|---|---|
| CTR-01 | Contract lifecycle | Draft, review, approve, sign, amend, perform, close, and void. |
| CTR-02 | Contract milestones | Time-, progress-, and event-triggered obligations and warnings. |
| CTR-03 | Payment applications | Link contract, milestone, budget, invoice, acceptance, and approval. |
| CTR-04 | Early and excess payment control | Block or escalate early payment and prevent overpayment. |
| CTR-05 | Amendments and changes | Recalculate commitment, budget, forecast, and approval consequences. |
| CTR-06 | Settlement and reconciliation | Reconcile contract, delivery, invoice, payment, payable, and ledger. |

### EXP — Expenses and employee finance

| ID | Capability | Minimum outcome |
|---|---|---|
| EXP-01 | Expense claim | Capture details, evidence, policy, allocation, and applicant. |
| EXP-02 | Budget precheck | Check and reserve budget before approval or payment. |
| EXP-03 | Employee advances and loans | Issue, track, repay, offset, and age balances. |
| EXP-04 | Automatic offset | Apply approved expenses against outstanding advances deterministically. |
| EXP-05 | Approval and payment | Separate claim approval, accounting recognition, and settlement. |
| EXP-06 | AI intake | Extract proposals from text or documents with confirmation and provenance. |

### SAL — Sales, customers, and marketing

| ID | Capability | Minimum outcome |
|---|---|---|
| SAL-01 | Customer master | Maintain customers, identity, relationships, consent, and status. |
| SAL-02 | Marketing | Plan campaigns, channels, materials, spend, leads, and effectiveness. |
| SAL-03 | Reservation and subscription | Record pre-contract intent, deposits, conversion, cancellation, and refund. |
| SAL-04 | Sales agreements | Create, approve, amend, perform, and terminate customer agreements. |
| SAL-05 | Receivables and collections | Schedule, recognize, collect, age, and reconcile receivables. |
| SAL-06 | Customer financing | Track mortgage or third-party funding milestones and exceptions. |
| SAL-07 | Revenue forecast | Connect planned and actual sales to project cash flow and performance. |

### FIN — Accounting, treasury, financing, and tax

The reference ERP supplies parts of these areas. The new product must complete
them rather than claiming parity at the operational-record level.

| ID | Capability | Minimum outcome |
|---|---|---|
| FIN-01 | Chart of accounts and books | Effective-dated accounts, dimensions, entities, currencies, and books. |
| FIN-02 | Journal and posting | Balanced immutable postings from controlled templates and source events. |
| FIN-03 | Payable and receivable subledgers | Reconcile obligations and rights to the general ledger. |
| FIN-04 | Accrual, prepayment, and deferral | Recognize economic events independently from cash timing. |
| FIN-05 | Assets | Capitalize, depreciate, impair, transfer, and dispose assets. |
| FIN-06 | Period close and statements | Close periods and produce reconciled financial statements. |
| FIN-07 | Consolidation | Support intercompany activity and group reporting. |
| FIN-08 | Cash and bank accounts | Maintain positions, statements, reconciliation, and controlled access. |
| FIN-09 | Treasury forecast | Forecast liquidity and schedule or release payments. |
| FIN-10 | Financing | Manage loans, facilities, interest, repayment, guarantees, and covenants. |
| FIN-11 | Tax determination | Apply effective jurisdiction, category, rate, withholding, and evidence rules. |
| FIN-12 | Tax filing and reconciliation | Prepare, review, file, pay, and reconcile tax obligations. |

### RPT — Reporting, warning, intelligence, and governance

| ID | Capability | Minimum outcome |
|---|---|---|
| RPT-01 | Group/company/project cockpit | Consistent KPIs with source traceability and drill-down. |
| RPT-02 | Standard reports | Operational, management, accounting, treasury, tax, and investment reports. |
| RPT-03 | Custom report builder | Controlled data models, filters, exports, and share policies. |
| RPT-04 | Warning rules | Configurable rules, scans, findings, ownership, resolution, and recurrence. |
| RPT-05 | Risk and control register | Link risks, controls, tests, exceptions, evidence, and remediation. |
| RPT-06 | AI assistance | Explain and propose from authorized source data with evidence and audit. |
| RPT-07 | Agent operations | Bound requests, authority ceilings, result schemas, review, and usage controls. |

## Capability specification template

Every capability must receive a specification before implementation or migration:

```text
Capability ID:
Business purpose:
Current users and owners:
Actors and represented principal:
Inputs and source records:
States and valid transitions:
Authority and segregation rules:
Business invariants:
Accounting consequences:
Tax consequences:
Evidence and retention:
Reports and warnings:
Existing ERP routes/tables/pages:
New owning package:
Migration mapping:
Parity scenarios:
Reconciliation query:
Rollback procedure:
Current parity state:
```

## Replacement gate

The old ERP cannot be retired merely because every screen has a counterpart.
Replacement requires:

- all site-critical capabilities at `cutover-ready` or `accepted`;
- opening balances and operational records reconciled;
- workflow and authority scenarios verified;
- financial totals reconciled by entity, period, project, party, and account;
- attachments and audit evidence accessible;
- production operations, backup, restore, monitoring, and support rehearsed;
- named business owners accepting each domain;
- a tested rollback within the agreed recovery window.
