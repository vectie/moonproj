# ERP marketing runtime audit

## Scope

The ERP marketing router (`../erp/erp_new/server/src/routes/marketing.js`)
owns campaign, placement, channel, and material reads plus mutations. This
slice migrates the four read families and a bounded local command seam;
campaign/placement spend, CBS consumption, attribution, and provider actions
remain company-domain gates.

## PostgreSQL boundary

The authenticated service and read-model adapter expose:

- `/api/company/marketing/campaigns?projGuid=&state=`
- `/api/company/marketing/placements?campaignGuid=`
- `/api/company/marketing/channels`
- `/api/company/marketing/materials?projGuid=`

Responses preserve source-shaped marketing metadata and carry
`source_coverage`, `missing_or_empty_source_tables`, and
`authorizing=false`. Imported rows are never mutated. Authority-checked local
commands persist PostgreSQL aggregate projections, idempotency receipts, and
audit events, then appear in the same reads with `sourceKind=command`:

- `POST /api/company/marketing/{campaigns,placements,channels,materials}`
- `PUT /api/company/marketing/campaigns/:guid`
- `PUT /api/company/marketing/placements/:guid/effect`
- `DELETE /api/company/marketing/{campaigns,channels,materials}/:guid`

## Current evidence

The controlled PostgreSQL export has zero rows for
`mkt_campaign`, `mkt_placement`, `mkt_channel`, and `mkt_material`. Rabbita
`/marketing` therefore shows an explicit empty source state after the four
reads succeed; its designer campaign/placement rows are retained only as
transport-failure fallback. The reviewed synthetic marketing cohort remains a
separate target rehearsal and is not promoted as imported ERP production data.

## Open gates

Campaign/placement/channel/material local create/update/delete/effect commands
are now covered by service and trusted-gateway smoke tests, but browser
production identity and named-owner acceptance remain open. Budget/CBS
reservation, spend accounting, cash, attribution, provider execution, and
source-export reconciliation remain unimplemented external-effect gates.
