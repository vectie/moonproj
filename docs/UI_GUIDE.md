# MoonProj desktop UI guide

MoonProj is a basic OPC operating system. It keeps company facts, delegated
work, evidence, and release decisions in one control surface. The desktop app
uses Rabbita for the UI and Lepusa for the native window and local-service
lifecycle.

## Start here

1. **Products** is the default front door (Moon mode is not required). Read a product’s purpose, current authored intent, and PRD snapshot before entering its work.
2. **Company domain** establishes the legal/operating subject, authority, and
   owned resources.
3. **Task dispatch** records work, acceptance criteria, Agent execution, and
   Owner acceptance.
4. **Evidence and audit** shows who acted, under which authority, and what
   immutable receipt resulted.
5. **Release quality** asks MoonClaw to inspect one exact repository, branch,
   commit, version, and proposed tag.

UI drafts and design snapshots are not company facts. A change becomes a
formal fact only after the PostgreSQL service accepts it.

## Page inventory

| Page | Question answered | First action | Empty/error meaning |
| --- | --- | --- | --- |
| Products | Why does each product exist, and where are its documents and work? | Select a product by stable ID | Catalog, repository, document and detail-read failures are separate |
| Cockpit | What needs an Owner decision today? | Review pending decisions | Zero means no accepted fact currently requires action |
| Agent fleet | What delegated labor exists? | Inspect Agent authority and budget | Offline Agents cannot create accepted company facts |
| Task dispatch | Where is work in its lifecycle? | Prepare a local draft or recover a formal task | Browser drafts are separate from server task records |
| Project portfolio | Which delivery stage and Gate is current? | Select a project | Unknown means no accepted evidence |
| Moon projects | How close are Moon Suite products to release? | Open engineering evidence from Products, or use Moon mode | Missing siblings do not block the basic OPC |
| Release quality | Can this exact candidate ship? | Enter branch, version, and proposed tag | Unknown/fail/blocked keeps release locked |
| Observe | Are SLOs and error budgets healthy? | Review warnings | Missing telemetry is unknown, not healthy |
| Operate | Are incidents controlled and learned from? | Open an incident or runbook | No event does not prove readiness |
| Company domain | Does the company own and control its resources? | Establish the company and authority | Session records remain informal until persisted |
| Policy Radar | Which policy change deserves verification today? | Scan verified sources | Scores never imply law, funding, or procurement intent |
| Evidence and audit | What happened and why may we trust it? | Inspect receipts and authorization | Missing evidence prevents acceptance |
| Guide | How does the system work? | Follow the three-step start path | The guide is always available offline |

## Products, intent, documents, and work

Products reads the authenticated, versioned `/api/moonsuite/products` catalog independently of PostgreSQL, MoonClaw, MoonGate, and model providers. The configured twenty active definitions are not twenty installed, running, accepted, or release-ready products. The existing nine engineering enrollments are a subset. A configured repository path may be absent on the serving machine; an unknown path is a different state.

The product detail shows authored purpose and intent before engineering evidence. MoonProj is top-down management that produces concrete working results; MoonDesk supports quick prototyping and human interleaving; MoonTown supports bottom-up reuse and emergence; MoonBook supports accumulated agent experience and memory. Full source paragraphs and provenance remain visible. These intentions do not imply that the capabilities are implemented or accepted.

PRD downloads are deliberately packaged authored snapshots. They are not live Library synchronization or implementation-completion evidence. A download link is displayed only for the exact declared product/document route with `available` status and a supported URL. Missing bytes or a missing opener remain visible without an invented link.

Search, name ordering, catalog refresh, Products, and Release quality all retain string product identity. The same exact ID appears in Quality with Moon mode off. Selecting a product only reads demand admission and, for enrolled targets, engineering evidence. It does not start an audit or create a task. HTTP authentication errors, invalid responses, offline state, missing evidence, and stale evidence remain distinct; a detail failure does not erase the catalog.

A product ID is not a company-project ID. Where no durable mapping is configured, the detail says so. **Read company projects** loads actual company records. Selecting one is local to preparing work and does not persist a product-to-project mapping. **Read product tasks** reads `/api/company/tasks?product_id=…` across explicitly recorded company projects, without requiring a picker choice. Two products using the same company project still have separate work histories. Untagged legacy tasks remain unassigned and are available through exact task links and the existing company-project list.

**Prepare task** requires an active company project returned by that read. It opens or resumes an independent local draft with sourced product context, a blank acceptance description, and a blank execution workspace. A source repository is never silently used as the execution workspace. Product identity, company project and workspace remain separate fields. The saved product-definition snapshot survives browsing or catalog changes; canonical task attribution comes only from the task readback.

Choosing a suggested PRD outcome before a company project retains that outcome in the current page and opens the existing read-only project picker. The chosen title and next action stay visible while project reads are pending, empty or failed; the acceptance details remain expandable. After a valid project choice, **Prepare selected work** carries the same requirement IDs and acceptance into the ordinary draft. Reads and project selection never create or start a task. Repeated clicks reuse the pending read or existing matching draft. Cancel, a different product, or a refreshed catalog clears the temporary choice; page reload does not restore it until it has become a saved draft. Edited or attempted drafts are resumed intact, with an explicit notice rather than overwritten scope.

The selected formal task and its native execution/report state are separate from the draft editor. Preparing B while A is running, submitted, interrupted, or loading does not overwrite A or accept its results. Repeated Prepare resumes the current matching product/project draft; **New draft** creates another slot. Close, browsing and task navigation park drafts. The local list can restore or explicitly remove a chosen draft without deleting any formal task. Generic and policy drafts do not inherit a product tag.

Drafts and recent task IDs are saved in a versioned browser-local record scoped to the authenticated actor. This contains ordinary draft fields and IDs, not credentials, cookies, headers, signing authority or provider secrets. Storage failure is visible; the first Create POST is withheld until its identity/request fields have been saved. Pre-POST failures remain editable. Browser storage is not a server backup and is not synchronized between devices; clearing it can remove unsent drafts. Concurrent editing from several tabs is not a supported draft merge workflow.

Each draft gets a unique task ID and idempotency key before Create; the ordinary request fields freeze when sending. Lost, malformed, conflicting or unavailable responses remain uncertain. Restore performs an exact GET for the retained task ID before any retry. Only an exact404 enables the user's explicit same-ID, same-key, same-body retry; authentication failures do not trigger Create. Reloaded in-flight drafts always recover first. Known noncommitting400/422 responses and the exact active-project409 validation can be revised explicitly into a new draft identity, preserving the original ID. If an earlier attempt was ambiguous, later validation failures do not erase that uncertainty. A matching receipt or canonical exact record confirms the created task; no draft creates a completion fact.

Task rows and recent IDs have canonical `?task=` links. Explicit task selection pushes browser history; reload and Back/Forward read exact records without starting execution. The URL takes precedence over the pre-existing single-ID browser breadcrumb, which remains only a navigation hint for old tasks. The task's current product association and the report's product-at-creation snapshot are displayed separately; absent or removed catalog definitions use the raw recorded ID. Legacy missing product identity remains unassigned.

Start, native execution completion, Submit, and Accept remain separate. Native run/session/command identity and reserved request bytes are not regenerated by drafting, navigation, or a product retag. Browser keyboard, narrow-viewport, and live desktop interaction verification must still be completed in a permitted browser environment; reducer/HTML/transport checks do not substitute for browser acceptance.

## One nine-Gate release system

The three visible dimensions are projections of the same commit-level ledger:

- **How far**: the last consecutively passed Gate.
- **How well**: failures, blockers, unknowns, and reviewed findings.
- **Production quality**: whether G1–G9 and redlines R1–R3 permit an Owner
  authorization request.

G1 identifies intent and candidate; G2 covers functional completeness; G3 UI,
accessibility and guidance; G4 build/test quality; G5 integration and data;
G6 security/compliance; G7 artifacts and compatibility; G8 install/recovery;
and G9 repository, tag, checksum, signing, and release control.

An `accept` review verdict means the evidence is trustworthy. It does not mean
the candidate is production-eligible.

## Desktop data and recovery

Lepusa starts two loopback-only MoonBit sidecars: the company service and the
Rabbita gateway. PostgreSQL remains the system of record. The release does not
bundle a database password.

For password-authenticated local PostgreSQL, create a standard `pgpass` file at
the Lepusa app-data directory for `dev.vectie.moonproj`, with mode `0600`.
Alternatively launch from an environment that supplies normal `PGHOST`,
`PGPORT`, `PGUSER`, `PGDATABASE`, and `PGPASSWORD` variables. Never place these
values in the app bundle.

If PostgreSQL is unavailable, the desktop shell remains understandable but
data reads and commands fail closed. If MoonClaw or the Moon Suite workspace is
unavailable, engineering evidence remains unknown and release stays locked.

Closing the final MoonProj window stops both supervised services. User data is
kept under `LEPUSA_APP_DATA_DIR`; the signed app bundle must remain unchanged.

## Preview limitations

- This preview is ad-hoc signed and not notarized. On first launch, macOS may
  require Control-click → Open.
- PostgreSQL 18 and `psql` are external prerequisites in this build.
- MoonClaw and local sibling repositories are external prerequisites for live
  engineering audits.
- The real-estate ERP extension remains a separately enabled pack.
