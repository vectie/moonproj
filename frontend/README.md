# ERP frontend clone (Rabbita)

This browser surface is a Rabbita port of the designer-built ERP shell in
`../erp/erp_new/web`: the login page, dark navigation hierarchy, header, and
group dashboard are copied from the source UI language and labels.

The dashboard is currently an explicit read-only fixture while the HTTP/API
boundary is being connected. The remaining ERP routes are mounted as honest
migration placeholders so the full navigation can be reviewed before each
page is ported. Build and preview it with Warren:

```sh
moon install moonbit-community/warren
warren dev frontend/main --public-dir frontend/public
```

The UI intentionally stays within the source product’s Element Plus visual
language: system Chinese fonts, `#1e293b` navigation, `#f1f5f9` work canvas,
compact KPI cards, and the source login gradient.
