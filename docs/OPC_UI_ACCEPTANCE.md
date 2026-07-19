# Basic OPC UI Acceptance

Recorded: 2026-07-20

## Product boundary

`frontend/opc` is the standalone, industry-neutral Basic OPC browser product.
It does not import or embed the designer real-estate ERP surface. The latter
remains in `frontend/main` as the UI of the `real-estate-erp` extension pack.

The base interface starts with an unnamed company and zero invented operating
metrics. MoonSuite siblings appear only as optional integration boundaries;
Moonfish investment agents are presented as a native absorption direction.

## Screen map

| Route | Operating responsibility |
|---|---|
| `/overview` | Setup progress, operating circuits, and truthful blank state |
| `/company` | Company identity, owned resources, roles, and rights |
| `/market` | Customers, demand, and market evidence |
| `/delivery` | Work, ownership, acceptance, and delivery evidence |
| `/commerce` | Commitments, counterparties, and exchanges |
| `/finance` | Ledger, cash, tax, financing, and investment boundaries |
| `/assurance` | Governance, audit, risk, and continuity |
| `/extensions` | Optional agents, MoonSuite awareness, and extension packs |

The first-session workflow can explicitly create a company profile, customer
signal, work item, commitment, basic ledger, and continuity plan. Completing
those actions advances setup from 0/6 to 6/6. Each creation surface states that
the result is local UI-session state, not a durable PostgreSQL business record.

## Browser acceptance

The Warren development build was exercised in the in-app browser at these
viewport sizes:

| Viewport | Result |
|---|---|
| 1440 × 900 | All eight navigation destinations render; no horizontal overflow |
| 768 × 1024 | Completed 6/6 state renders; no horizontal overflow |
| 375 × 812 | Drawer opens, navigation changes page, and drawer closes |
| 320 × 700 | Narrow layout remains within the viewport |

The browser flow also submitted the company, customer, work, commitment,
ledger, and continuity actions. Controls use explicit button types so actions
do not accidentally submit or reload enclosing forms.

## Run and verify

```sh
warren dev frontend/opc --public-dir frontend/opc_public --port 4300
scripts/build_opc_frontend.sh /tmp/moonproj-opc-dist
moon check frontend/opc --target js --warn-list +unnecessary_annotation
moon test frontend/opc --target js
moon build frontend/opc --target js
```

Durable PostgreSQL commands, authenticated company scope, reload persistence,
and operational record reconciliation are the next implementation boundary.
This acceptance record does not claim those runtime effects exist.
