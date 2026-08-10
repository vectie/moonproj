# Policy Intelligence and Business Opportunity Tracker

This component turns versioned government guidance into evidence-linked,
reviewable business hypotheses. It is designed for a company operating in
China that needs to notice policy wording early without treating policy
language as law, budget approval, procurement intent, or permission to act.

## What the component does

1. stores immutable document versions with issuer, date, jurisdiction, source,
   and a configurable authority rank;
2. compares clauses between versions;
3. detects new and retired terms inside Chinese or ASCII quotation marks;
4. tracks configured wording from weak/general to strong/specific;
5. builds a small knowledge graph linking document, issuer, jurisdiction,
   signal, opportunity, and target audience;
6. ranks B2B, B2G, and dual-lane hypotheses with the matched phrase and source;
7. attaches validation actions and an explicit professional-review boundary.

The second slice adds:

8. a small official-source candidate registry whose entries begin unverified;
9. reviewed policy-alert conversion into an in-app notification draft without
    delivery side effects; and
10. a Policy Radar UI for sources, change triage, side-by-side wording review,
    graph/list exploration, and B2B/B2G validation queues.

The runtime integration adds:

11. an authenticated PostgreSQL projection at
    `GET /api/company/policy/radar`;
12. signed, idempotent source-review and change-review commands at
    `POST /api/company/policy/sources/:id/reviews` and
    `POST /api/company/policy/changes/:id/reviews`;
13. persisted review receipts, audit records, and notification
    drafts whose delivery effect remains disabled;
14. UI loading, unavailable, stale, empty, and ready states, with exact
    reviewer evidence displayed after readback; and
15. a gated handoff from a confirmed opportunity to the existing Dispatch
    task form, plus a link from the review receipt to the Evidence page.

The built-in `changping_development_signal_rules()` catalog contains the seed
vocabulary supplied for this project: municipal compute nodes, advanced
energy, university technology transfer, AIGC, Changping Youth, Huitian Brain,
Changhuida, Changxiangban, and urban governance. This catalog is configuration,
not a claim that the supplied passages are authentic or still current.

## Analysis flow

```text
document text
        |
        v
immutable PolicyDocument version
        |
        +--> exact clause diff
        +--> unconfigured quoted-term discovery
        +--> configured signal/intensity matching
                         |
                         v
 evidence-linked knowledge graph
                         |
                         v
 B2B / B2G hypothesis ranking
                         |
                         v
 human source, legal, procurement, and market validation
```

Run the deterministic demonstration with:

```sh
moon run cmd/policy_intelligence
```

The analysis engine is pure and deterministic. Official webpage/PDF fetching
is intentionally left as a later, simple adapter; the first release focuses on
text comparison, review, and business validation rather than capture
infrastructure.

## UI and runtime contract

The Policy Radar navigation item lives in the Governance section of the OPC
shell. Opening it triggers a real authenticated request; the frontend does not
replace transport or schema failures with a successful sample view.

The current PostgreSQL projection intentionally reports
`freshness="stale"` and `capture_state="manual_refresh"`. This keeps the
candidate catalog visible without implying that an official-source poll has
already run.

Review order is fail-closed:

1. an Owner verifies or rejects the official-source candidate with exact
   evidence;
2. only a change whose source is currently verified can be confirmed or
   rejected;
3. confirmation creates a notification **draft**, never a delivery;
4. only a confirmed change unlocks “prepare validation task”; and
5. the prepared task still uses the existing Dispatch save command and its
   existing owner/date/evidence requirements.

All Policy Radar projections and receipts carry
`legal_effect=false` and `procurement_effect=false`. A score, source review,
change confirmation, draft notification, or prepared task is not evidence of
law, budget, purchasing intent, authorization, or a government commitment.

Run the targeted runtime checks with:

```sh
moon test frontend/opc/policy_radar_wbtest.mbt --target js
moon test cmd/postgres_company_service/main_wbtest.mbt --target native
moon test cmd/postgres_company_gateway/main_wbtest.mbt --target native
```

When local loopback and PostgreSQL access are available, run the persistence,
gate, draft, readback, and idempotent-replay smoke with:

```sh
scripts/company_postgres_policy_radar_smoke.sh
```

## Recommended next slices

- entity resolution across Beijing, district, department, park, company, and
  named program;
- a lightweight scheduled official webpage/PDF fetcher and text update;
- opportunity CRM states: observed, validated, sponsored, procurement-open,
  won, rejected, and expired;
- precision/recall evaluation using a human-labelled policy-change set.

No opportunity should move beyond validation solely because it has a high
score. B2G work additionally requires confirmation of responsible authority,
budget and procurement route; B2B work requires evidence of a paying customer
problem.

## Initial official-source candidates

- Beijing municipal portal PDF: the 2026 Changping planning document used to
  validate wording such as `3+N算力中心体系`, `北京市级算力节点`, `昌慧达`,
  and the advanced-energy 2030 target.
- Beijing Municipal Development and Reform Commission page: the January 2026
  report on Yin Li participating in the Changping delegation review.

These are candidate records, not automatically trusted facts.
