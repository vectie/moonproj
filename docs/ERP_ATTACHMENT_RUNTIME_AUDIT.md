# ERP attachment runtime audit

## Scope

The ERP attachment router (`../erp/erp_new/server/src/routes/attachment.js`)
defines metadata reads (`GET /list`, `/all`, `/stats`) alongside binary download,
upload, deletion, and OCR re-extraction. This migration slice covers the
metadata reads plus a signed OCR re-extraction candidate. The company product
must not claim binary ownership until the source files and an authorized object
store have been migrated.

## PostgreSQL boundary

The authenticated service and read-model adapter expose:

- `/api/company/attachments/list?bizType=&bizGuid=`
- `/api/company/attachments/all?bizType=&uploadedBy=&aiStatus=&keyword=`
- `/api/company/attachments/stats`
- `/api/company/attachments/download/:guid` (source-compatible missing-record
  or missing-binary boundary; never returns a local fixture file)

Each response is source-compatible where metadata exists and carries
`source_coverage`, `missing_or_empty_source_tables`, `authorizing=false`,
`downloadable=false`, and `binary_storage=not_imported`. The source envelope
allow-list is `attachment` plus `sys_user`; no local company aggregate,
notification, warning, or command record is written.

## Current evidence

The controlled PostgreSQL export has five imported `sys_user` rows and zero
`attachment` rows. The three reads therefore return an explicit empty source
state (`total=0`, `bytes=0`) rather than designer fixture files. The Rabbita
`/attachments` screen renders that state after a successful read and only uses
its reviewed fixture rows when the transport fails.

The parity matrix marks source `GET /list`, `/all`, and `/stats` as
`connected_attachment_read` and the download route as a
`connected_attachment_boundary`; signed `POST /upload`, `DELETE /:guid`, and
`POST /re-extract/:guid` are now explicit upload/delete/OCR candidates. The
current matrix leaves actual binary storage/serving and OCR provider execution
gated.

## Open gates

Multipart upload, binary download/preview beyond the missing-data boundary,
object deletion, provider-backed OCR re-extraction, retention,
malware scanning, object-store ownership, production identity, and owner
acceptance remain unimplemented gates. No attachment migration cutover is
authorized by this read-only slice.

The trusted PostgreSQL gateway now forwards the upload candidate, and the
Rabbita attachment header exposes the same bounded control. The candidate
returns the existing no-multipart/object-storage boundary without persistence;
`scripts/company_postgres_attachment_gateway_smoke.sh` proves authenticated
forwarding and the 409 no-side-effect response. Rabbita now also exposes the
OCR re-extraction candidate, selecting the first imported attachment when one
exists and otherwise showing the explicit source-404 boundary; the same smoke
proves dynamic gateway forwarding without OCR/provider execution or persistence.
