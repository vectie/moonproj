# ERP frontend clone (Rabbita)

This browser surface is a Rabbita port of the designer-built ERP in
`../erp/erp_new/web`: the login page, dark navigation hierarchy, header, and
dashboard are copied from the source UI language and labels. The major ERP
route families now have their own screen compositions—projects, plans,
workflow, AI, sales, cost/procurement, finance, analysis, and system
administration—with the source tables, tabs, KPI cards, and action boundaries
represented as read-only fixtures.

The UI is deliberately fixture-backed while the HTTP/API boundary is being
connected. It is a visual and interaction migration, not a claim that a button
already mutates company data. Representative project, contract, expense,
loan, and supplier detail/new flows now open as source-shaped forms with
explicit return/save/submit boundaries. The dashboard now reads the
PostgreSQL projection summary through the fixed read-only development adapter
`scripts/company_postgres_read_model_server.py`; command/mutation endpoints,
authentication, pooling, and production deployment remain separate gates.
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

The UI intentionally stays within the source product’s Element Plus visual
language: system Chinese fonts, `#1e293b` navigation, `#f1f5f9` work canvas,
compact KPI cards, dense data tables, and the source login gradient.
