# ERP marketing runtime audit

## Scope

The ERP marketing router (`../erp/erp_new/server/src/routes/marketing.js`)
owns campaign, placement, channel, and material reads plus mutations. This
slice migrates the four read families only; campaign/placement spend, CBS
consumption, attribution, and provider actions remain company-domain gates.

## PostgreSQL boundary

The authenticated service and read-model adapter expose:

- `/api/company/marketing/campaigns?projGuid=&state=`
- `/api/company/marketing/placements?campaignGuid=`
- `/api/company/marketing/channels`
- `/api/company/marketing/materials?projGuid=`

Responses preserve source-shaped marketing metadata and carry
`source_coverage`, `missing_or_empty_source_tables`, and
`authorizing=false`. No target campaign cohort or local command projection is
used to fill a successful source read.

## Current evidence

The controlled PostgreSQL export has zero rows for
`mkt_campaign`, `mkt_placement`, `mkt_channel`, and `mkt_material`. Rabbita
`/marketing` therefore shows an explicit empty source state after the four
reads succeed; its designer campaign/placement rows are retained only as
transport-failure fallback. The reviewed synthetic marketing cohort remains a
separate target rehearsal and is not promoted as imported ERP production data.

## Open gates

Campaign/placement/channel/material create, update, delete, effect tracking,
budget/CBS reservation, spend accounting, cash, attribution, production
identity, and owner acceptance remain unimplemented gates.
