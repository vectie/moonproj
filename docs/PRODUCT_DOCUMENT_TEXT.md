# Packaged PRD text for native product work

The source of each execution-text snapshot is the actual declared DOCX under
`resources/product-documents`, not its authored JSON or a product summary. The
original DOCX remains the ordinary downloadable document. This build-time data
preparation does not add a runtime Python dependency or a document admission gate.

## Prepare and verify

From a source checkout, with MoonBit and Info-ZIP `unzip` on PATH:

```sh
moon run scripts/prepare_product_document_text.mbtx .
moon run scripts/prepare_product_document_text.mbtx . --check
python3 scripts/verify_product_catalog.py
```

The repository argument is explicit, so the script also works from an unrelated
working directory. Preparation reads every source and computes every result
before writing sidecars and the manifest. Malformed archives/XML fail with an
error before writes. Unsupported but parseable body content produces a declared
`partial` extraction with specific limitations instead of being called complete.
The `--check` command is read-only and independently extracts the actual DOCX to
compare full text bytes and all extraction metadata. The existing catalog
verifier checks resource inventory, snapshot hashes, UTF-8, and declared sidecar
metadata. Run both checks when updating a release snapshot.

Regressions (the source workspace contains `prd_work/content/`):

```sh
moon check scripts/prepare_product_document_text.mbtx
moon run scripts/prepare_product_document_text.mbtx . --test /path/to/source-workspace
python3 scripts/test_product_catalog_data.py
moon fmt --check scripts/prepare_product_document_text.mbtx
```

The regression mode also requires Info-ZIP `zip` to create temporary fixture
archives and `cp` to isolate resource copies. Tests cover the 20 real PRDs,
paragraph/table ordering, source text runs, every functional requirement ID and
statement, acceptance tests and non-goals, renderer-added evidence statements,
malformed ZIP/XML, unsupported content, deterministic output, and stale data.
Authored JSON is used only for additional inclusion assertions, never extraction.

Script dependencies are pinned in the `.mbtx` import header:

- `Milky2018/xml@0.5.0`: namespace-aware XML 1.0 and entity parsing, Apache-2.0
- `moonbitlang/async@0.22.4`: filesystem and direct process execution, Apache-2.0
- `moonbitlang/x@0.4.50/crypto`: SHA-256, Apache-2.0
- Core JSON, UTF-8 and environment APIs from the selected MoonBit toolchain

The XML package is published through the Mooncakes registry; its upstream is
<https://github.com/moonbit-community/xml-mbt>. It accepts UTF-8 XML 1.0;
unsupported XML encodings/versions and unresolved external entities are errors.
No custom XML tokenization or lossy regular-expression parser is used. `unzip`
provides archive CRC checks and raw member reads. XML parsing, traversal,
coverage reporting, hashing, generation, and test orchestration run in MoonBit.
These are script-only build dependencies: `moon.mod`, service/gateway packages,
and app runtime dependencies are unchanged.

`lepusa.json` already bundles the entire `resources/product-documents` directory.
That existing directory rule includes `manifest.json` and its declared `text/`
sidecars. No additional launcher dependency is needed.

## Lookup contract

Keep `moonsuite.product-documents.v1` and existing asset fields unchanged. Find
an `assets[]` record using both `product_id` and `document_id`. Its `path` still
names the original DOCX. The additive `text_extraction` record is:

```json
{
  "schema": "moonsuite.product-document-text.v1",
  "path": "text/MoonProj_PRD.txt",
  "media_type": "text/plain; charset=utf-8",
  "source_docx_sha256": "SHA256_OF_ACTUAL_DOCX_BYTES",
  "source_docx_size_bytes": 48647,
  "text_sha256": "SHA256_OF_UTF8_TEXT_BYTES",
  "size_bytes": 36482,
  "extraction_version": "docx-body-v1",
  "coverage": "complete",
  "limitations": ["Explicit body scope", "Explicit formatting limitations"],
  "counts": {
    "paragraphs": 353,
    "tables": 1,
    "table_rows": 3,
    "table_cells": 9
  }
}
```

The example placeholders are descriptive; packaged records contain actual hashes
and the full limitations. Paths are declared relative to the document resource
root; consumers must read this field rather than guess a filename. There is no
change to the product catalog schema.

`complete` means all supported visible main-body paragraph/table text, in source
order. It does not mean a faithful page rendering or complete content from every
DOCX part. Headers, footers, comments, metadata, page layout, styling, list-label
glyphs and table geometry are explicitly outside scope. Paragraph boundaries are
newlines; table cells use tabs and rows use newlines. Stored whitespace, inline
text, Unicode, tabs, line breaks and literal requirement numbering are retained.

Drawings, embedded objects, imported altChunks, referenced notes, tracked edits,
fields, content controls, numbered-list labels, merged table-cell associations,
hidden-text formatting, alternate representations and unrecognized body elements
are detected and reported as `partial`. Some safely readable descendant or cached
text may be retained, as the specific limitations explain. Deleted/moved-out
text, drawings and alternate representations are omitted rather than represented
as normal prose or duplicated. New unsupported content must never be silently
labeled complete.

## Snapshot freshness

`source_docx_sha256` and `source_docx_size_bytes` describe the bytes used for that
extraction. Existing asset `source_sha256` / `packaged_sha256` and catalog metadata
remain the original declared release snapshot until deliberately updated.
Preparation does not rewrite that provenance to hide an ordinary document edit.
Text bytes and their hashes are independent fields. Runtime consumers can use
these facts to label missing, stale or partial context truthfully. A mismatch is
not authorization to deny an ordinary document download or block unrelated work.

The current corpus has 20 complete supported-body extractions totaling 517,601
UTF-8 bytes. It includes all 242 functional requirements, 666 functional acceptance
statements, 82 non-goals, 138 workflow acceptance criteria, and 102 nonfunctional
requirements with their tests. These are intended product requirements, not a
claim that the product has implemented or passed them.
