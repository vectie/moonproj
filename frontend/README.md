# ERP frontend clone (Rabbita)

This browser surface is a Rabbita port of the designer-built ERP in
`../erp/erp_new/web`: the login page, dark navigation hierarchy, header, and
dashboard are copied from the source UI language and labels. The major ERP
route families now have their own screen compositions—projects, plans,
workflow, AI, sales, cost/procurement, finance, analysis, and system
administration—with the source tables, tabs, KPI cards, forms, and action
boundaries represented as read-only fixtures. Inbox, attachments, health,
users/roles, profile, notifications, OCR, and webhook routes now retain their
distinct source layouts instead of sharing a generic administrative table.
The report center also opens a read-only `/share/:token`-shaped cost report
preview with the source metadata bar, dense summary table, expiry label, and
public-link boundary.
Detail routes accept arbitrary source identifiers (`/projects/:id`,
`/contracts/:id`, `/expenses/:id`, `/loans/:id`, and
`/srm/providers/:id`) instead of being limited to the reviewed fixture IDs;
the source dashboard redirect aliases are retained as well.

The UI is deliberately fixture-backed while the HTTP/API boundary is being
connected. It is a visual and interaction migration, not a claim that a button
already mutates company data. Representative project, contract, expense,
loan, and supplier detail/new flows now open as source-shaped forms with
explicit return/save/submit boundaries. The dashboard now reads the
PostgreSQL projection summary through the fixed read-only development adapter
`scripts/company_postgres_read_model_server.py`. The authenticated bounded
runtime is available separately as `scripts/company_postgres_service.py`. Its
local command verticals include the expense lifecycle documented in
`docs/ERP_EXPENSE_RUNTIME_VERTICAL.md`, the contract lifecycle documented in
`docs/ERP_CONTRACT_RUNTIME_VERTICAL.md`, and the payment-application lifecycle
documented in `docs/ERP_PAYMENT_APPLICATION_RUNTIME_VERTICAL.md`, and the
procurement/tender lifecycle documented in
`docs/ERP_PROCUREMENT_RUNTIME_VERTICAL.md`. The
new-expense and contract routes are wired to local
create/submit/reject/resubmit/approve loops, while `/payment-applies` also
loads real application rows and exposes edit/void plus milestone eligibility
controls through the local-only development gateway below; `/tender` now loads
tender projections and exposes local planning/publish/bidding/cancellation
controls. Imported tender rows remain read-only and award requires a qualified
supplier projection. `/srm/providers` now loads supplier qualification and
scope projections while its detail/new command form remains fixture-backed.
The other route families remain fixture-backed.
Command-gateway
production deployment, identity/token integration, and managed rollback remain
separate gates.
Build and preview it with Warren:

```sh
moon install moonbit-community/warren
warren dev frontend/main --public-dir frontend/public
```

To exercise the PostgreSQL-backed read model and serve the built browser
surface from one local origin:

```sh
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  python3 scripts/company_postgres_read_model_server.py \
  --public-dir /path/to/warren/dist
```

To exercise the connected expense, contract, payment-application, or tender
create/submit/reject/resubmit/approve paths, keep the service token
on the server side and put the local gateway in front of the browser bundle:

```sh
export MOONPROJ_SERVICE_TOKEN=choose-a-local-token
export PGPASSWORD=your-local-password
export MOONPROJ_DEV_USER=chengyuzhe
export MOONPROJ_DEV_PASSWORD=123456
export MOONPROJ_ACTOR_SIGNING_SECRET=choose-a-local-signing-secret
python3 scripts/company_postgres_service.py --database moonproj \
  --port 4174 --require-forwarded-tls \
  --actor-signing-secret-env MOONPROJ_ACTOR_SIGNING_SECRET
python3 scripts/company_postgres_dev_gateway.py \
  --public-dir /path/to/warren/dist --port 4173 --service-port 4174
```

Open `http://127.0.0.1:4173`. The gateway establishes an in-memory HttpOnly
session from the configured local credentials, forwards `/api/` requests with
the bearer token and HTTPS-forwarding marker, and signs the session actor
assertion before forwarding it to the service. It also translates the Rabbita
form's JSON `idempotency_key` into the command header required by the service.
It is intentionally a local development adapter: it binds to loopback, only
allow-lists expense, contract, and payment-application POST commands, and is
not the production deployment.

The UI intentionally stays within the source product’s Element Plus visual
language: system Chinese fonts, `#1e293b` navigation, `#f1f5f9` work canvas,
compact KPI cards, dense data tables, and the source login gradient.
