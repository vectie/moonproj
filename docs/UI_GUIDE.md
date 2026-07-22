# MoonProj desktop UI guide

MoonProj is a basic OPC operating system. It keeps company facts, delegated
work, evidence, and release decisions in one control surface. The desktop app
uses Rabbita for the UI and Lepusa for the native window and local-service
lifecycle.

## Start here

1. **Company domain** establishes the legal/operating subject, authority, and
   owned resources.
2. **Task dispatch** records work, acceptance criteria, Agent execution, and
   Owner acceptance.
3. **Evidence and audit** shows who acted, under which authority, and what
   immutable receipt resulted.
4. **Release quality** asks MoonClaw to inspect one exact repository, branch,
   commit, version, and proposed tag.

UI drafts and design snapshots are not company facts. A change becomes a
formal fact only after the PostgreSQL service accepts it.

## Page inventory

| Page | Question answered | First action | Empty/error meaning |
| --- | --- | --- | --- |
| Cockpit | What needs an Owner decision today? | Review pending decisions | Zero means no accepted fact currently requires action |
| Agent fleet | What delegated labor exists? | Inspect Agent authority and budget | Offline Agents cannot create accepted company facts |
| Task dispatch | Where is work in its lifecycle? | Create work with acceptance criteria | Session-only drafts are not persisted |
| Project portfolio | Which delivery stage and Gate is current? | Select a project | Unknown means no accepted evidence |
| Moon projects | How close are Moon Suite products to release? | Enable Moon mode and select a product | Missing siblings do not block the basic OPC |
| Release quality | Can this exact candidate ship? | Enter branch, version, and proposed tag | Unknown/fail/blocked keeps release locked |
| Observe | Are SLOs and error budgets healthy? | Review warnings | Missing telemetry is unknown, not healthy |
| Operate | Are incidents controlled and learned from? | Open an incident or runbook | No event does not prove readiness |
| Company domain | Does the company own and control its resources? | Establish the company and authority | Session records remain informal until persisted |
| Evidence and audit | What happened and why may we trust it? | Inspect receipts and authorization | Missing evidence prevents acceptance |
| Guide | How does the system work? | Follow the three-step start path | The guide is always available offline |

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
