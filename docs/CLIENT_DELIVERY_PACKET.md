# Client delivery packet

In a formal task whose accepted report uses a retained human revision, open
**已保存报告与接受记录 → 准备客户交付包 → 预览交付包**. The existing authenticated
accepted-human-result read prepares the exact captured text. No new approval
or acknowledgment step is added.

1. Inspect the result body. Optionally edit **交付标题**, **结果文件名**,
   **交付说明**, and **审阅请求**. The filename defaults to the retained source
   basename, or `delivered-result.txt` when that basename is unsuitable.
2. Click **下载交付包 ZIP**. The ZIP contains the named result and a friendly
   `README.txt` with the handoff note. The outer ZIP uses the editable result
   filename plus `.zip`, without a task identifier.
3. **可选技术来源** can additionally include the unchanged
   `source-observation.json`. It is off by default. The existing
   **下载已接受人工修订 JSON** action remains available and unchanged.

## Practical limits

- This slice supports only immutable accepted human-revision UTF-8 text, up to
  256 KiB. Empty text is valid. It does not export arbitrary native/continuation
  files, binary files, or remote URLs.
- The result preserves the original bytes, including a UTF-8 BOM and line
  endings. A `.md`, `.csv`, or other editable extension does not convert content.
- Filenames are portable basenames, not paths. `README.txt` and
  `source-observation.json` are reserved case-insensitively.
- Notes stay in this page only. Closing the preview, changing task/report/source
  context, changing actor, or reloading clears preparation. A failed/30-second
  timed-out read can be retried; late and duplicate responses cannot replace a
  newer preparation. Repeated Prepare while ready preserves current edits.
- The default README does not copy task titles, internal acceptance criteria,
  PRDs, workspace paths, actor IDs, customer/contact data, or source metadata.
  The user should inspect the accepted result body before sharing it; that body
  is intentionally not rewritten or redacted.
- The ZIP is generated locally with stored entries and standard UTF-8 filename
  metadata. No data is sent to a customer, no delivery receipt is created, and no
  customer acceptance, invoice, payment, or Book review is inferred.

## Implementation and verification

`product/client_delivery` validates canonical Base64, strict UTF-8 round trip,
size, and SHA-256 before exposing a preview or building a deterministic ZIP.
`frontend/opc/dispatch_client_delivery*` separately binds the existing response
to the current accepted task/report/revision using the existing source checks.
No gateway/service route or persisted company schema changes.

Tests cover exact empty/Unicode/CRLF/BOM/maximum-sized bodies, same-length
modified bytes, unsupported encodings, safe and Unicode filenames, ZIP entries
and directory offsets, actual GET/download commands, editable README content,
technical source inclusion, retries/timeouts, close/navigation/task/actor/report
changes, and unchanged company state. Real produced ZIP files are also checked
with an independent unzip tool and extracted-byte comparisons.

This advances the local delivery-preparation portion of MOONPROJ-R04 and
MOONPROJ-R01. It does not complete either requirement's external delivery,
customer-response, financial, or live-service acceptance criteria. Cloud
source tests do not qualify a mounted browser, installed Mac, live PostgreSQL,
or configured model provider.
