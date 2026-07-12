# ERP MySQL Source Probe

Recorded: 2026-07-13  
Status: configured source discovered; listener unavailable

`../erp/erp_new/server/.env` contains the ERP's MySQL connection configuration.
The migration repository includes `scripts/erp_mysql_inventory.mjs`, a
read-only metadata probe that uses that configuration only to request:

- table names;
- row counts;
- primary-key columns.

It never selects business row payloads and never prints credentials, hostnames,
database names, or secrets. The probe uses a two-connection limit and a
10-second connect timeout.

The sandboxed probe was denied by the local network policy. An approved
read-only retry reached the configured endpoint but returned `ECONNREFUSED`.
No live MySQL inventory was produced. The 26-table SQLite snapshot and the
credential-free export contract therefore remain the authoritative migration
inputs until the ERP database listener is provisioned or a complete redacted
MySQL/JSON export is supplied.
