# ERP attachment runtime audit

## Scope

The ERP attachment router (`../erp/erp_new/server/src/routes/attachment.js`)
defines metadata reads (`GET /list`, `/all`, `/stats`) alongside binary download,
upload, deletion, and OCR re-extraction. This migration slice covers only the
metadata reads. The company product must not claim binary ownership until the
source files and an authorized object store have been migrated.

## PostgreSQL boundary

The authenticated service and read-model adapter expose:

- `/api/company/attachments/list?bizType=&bizGuid=`
- `/api/company/attachments/all?bizType=&uploadedBy=&aiStatus=&keyword=`
- `/api/company/attachments/stats`

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
`connected_attachment_read`; only binary download remains unconnected.

## Open gates

Upload, binary download/preview, deletion, OCR re-extraction, retention,
malware scanning, object-store ownership, production identity, and owner
acceptance remain unimplemented gates. No attachment migration cutover is
authorized by this read-only slice.
