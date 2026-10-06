# Product portfolio and document resources

## One catalog, separate authorities

`config/moonsuite-engineering.json` now uses `moonsuite.product-portfolio.v2`.
It is the single definition catalog for Products and gateway engineering-target
resolution. It contains twenty active product definitions, with the existing
nine engineering enrollments as an explicit subset. This replaces the old v1
`projects` array; a stale v1 file fails visibly instead of receiving invented rows.

Product identity, company-project identity and execution workspace are separate.
Catalog reads neither create company records nor infer a project by matching a
product ID. All initial `company_project_id` values are null. Product selection
never starts an audit or creates/dispatches a task. Existing company commands,
explicit task project selection and native dispatch remain their own authorities.

The Products project picker uses membership in a successfully read current
`GET /api/company/projects` list. The service uses the same
`project_plan_project_rows` source for task-create project existence checks;
deleted command/import projections are excluded there. `if_end` and
`proj_status` do not determine whether a listed project can prepare a task.
Native project creation itself emits `if_end: true` with an active projection.
A selected ID must still exist in the current successful list; a catalog
mapping alone is insufficient. If a project disappears after that read, the
service's existing create-time 409 remains authoritative. Local preparation
and its captured product/project identities do not bypass that check.

A product definition is not an installation or acceptance result. No maturity
score, progress percentage or service availability is derived from the list.
Founder intent is identified separately from authored PRD intent by the
`philosophy.source_kind`, `source` and `version` fields. Engineering observations
continue to come from the existing candidate-bound company evidence read model.

The catalog includes MoonProj, MoonBook, MoonClaw, MoonTown, MoonDesk, MoonGate,
MoonRobo, MoonMoon, MoonFish, MoonCast, MoonChat, MoonFind, MoonFlow, MoonFort,
MoonLib, MoonMold, MoonPoly, MoonEdit, MoonLeaf and MoonVis. MoonProp, Mooncake,
retired MoonStat, role/function aliases and supporting repositories are excluded.
LunaNexa is not an application-workflow row.

## Repository and engineering semantics

`repository.path` is relative to the serving machine's configured
`MOONSUITE_WORKSPACE_ROOT`. `repository.url` and `revision` are recorded source
provenance, nullable when unknown, and never assert remote reachability.
`repository.source_kind` distinguishes a source-manifest mapping from a merely
configured path. Presence is checked on the serving machine at request time;
a missing checkout is not an absent product and does not erase enrollment.

MoonFish retains its earlier configured `moonfish` target with unknown remote
origin and revision. It is missing in the cloud source snapshot but can resolve
on another machine that contains that configured checkout. MoonPoly, MoonEdit,
MoonLeaf and MoonVis have no known repository mapping and remain null.

Only products with `engineering_target` may use the existing audit command. New
inventory entries have no audit authority. The gateway and Products read the
same catalog; catalog order has no identity meaning. Audit target lookup uses
its stable ID and declared repository path instead of an independent name list.

## Authenticated reads

- `GET /api/moonsuite/products` returns `schema`,
  `scope: "active_product_definitions"` and `products` from the validated catalog
- A mapped repository adds `availability: "present" | "missing"`; an unknown
  repository remains null
- A document adds `availability: "available" | "missing" |
  "repository_unavailable"` and a usable relative `url` only when available
- `GET` or `HEAD /api/moonsuite/products/{product_id}/documents/{document_id}`
  serves a declared document, with the same existing session gate as other APIs
- No session or a tampered session returns 401. Unknown document/product IDs and
  unavailable declared files return 404. Unsupported methods return 405
- Missing/unreadable catalog returns 503 with `product_catalog_missing`;
  malformed/schema-invalid catalog returns 503 with `product_catalog_invalid`
  and no substitute product rows

List/document reads run entirely in the gateway. PostgreSQL, MoonClaw, MoonGate
and a model provider are not prerequisites. Engineering/admission/company work
reads can fail independently without changing the definition catalog.

## Real document snapshots

`resources/product-documents` contains the twenty actual authored DOCX PRDs.
The resource manifest records their provenance, hashes and captured Library
identities. A Library ID is provenance, not a URL. These are bundled authored
snapshots, with `library_captured_version_number` identifying the version in the
delivery receipt. The application does not synchronize them with current Library
contents or promise a live-current version.

Hashes and versions describe the declared packaged snapshot. The catalog asset
validator checks release-copy fidelity; it is not a runtime editing or security
gate. The reader serves the current bytes of a declared regular document and
does not deny ordinary edits because their hash differs. When replacing a
packaged snapshot for release, update its catalog/manifest metadata as well.

DOCX responses use the official Word document MIME type and attachment filename.
If a future catalog declares a verified repository README/contract `.md`, the
same narrow route serves it as plain text, never executable HTML. Only catalog
product/document IDs enter the route: clients cannot supply a filesystem path.
The reader checks relative declaration paths, resolved root containment,
regular-file kind and a 16 MiB size bound. Missing/unreadable or out-of-root
resources are unavailable, not clickable scratch paths or guessed remote links.

## Launch and resource configuration

The gateway supports these explicit locations:

| Configuration | CLI override | Source-checkout default |
| --- | --- | --- |
| `MOONPROJ_PRODUCT_CATALOG` | `--product-catalog` | `config/moonsuite-engineering.json` |
| `MOONPROJ_PRODUCT_DOCUMENT_ROOT` | `--product-document-root` | `resources/product-documents` |
| `MOONSUITE_WORKSPACE_ROOT` | `--moonsuite-workspace-root` | Existing gateway parent-directory default |

The defaults above are only a source-checkout convenience. Packaged execution
uses explicit paths: `lepusa.json` bundles the catalog under `config/` and the
PRDs under `product-documents/`; `moonproj_desktop_service.sh` exports both paths
relative to `LEPUSA_RESOURCE_DIR`, independently of the process cwd. Its default
workspace root is the app-data `workspaces/` directory, unless explicitly
configured. A repository root is not an execution-workspace grant.

Lepusa readiness now uses local `GET /ready`, which reports gateway readiness
without requiring a valid catalog or a working company service. This permits the
window to open and show an explicit catalog error. Existing `/health` still
reports company-service health and may return 503 while Products remains usable.
The launcher keeps the gateway running even when the company service exits.
Existing loopback desktop session bootstrap and standalone native MoonClaw
control discovery are unchanged.

## Verification

Run the pure parser and gateway tests with the cached MoonBit toolchain:

```sh
moon test engineering/registry --target native --strip -j 1
moon test cmd/postgres_company_gateway --target native --strip -j 1
moon test cmd/postgres_company_service --target native --strip -j 1
```

`scripts/verify_product_gateway.py` runs real-native authenticated HTTP checks,
verifies each PRD's exact bytes/MIME/disposition, exercises configuration errors,
missing resources, ID-only routes and existing audit membership. With `--launcher`
it invokes the actual desktop service script from an unrelated directory using
a packaged resource layout and an intentionally exiting company-service stub.
This is a cloud-OS packaged-layout test, not a macOS bundle, signing or installed
app validation. The UI must also be built and exercised with these endpoints;
passing gateway tests alone does not establish UI or end-to-end company acceptance.
