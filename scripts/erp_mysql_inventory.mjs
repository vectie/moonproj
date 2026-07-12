#!/usr/bin/env node

// Read-only metadata probe for the ERP's configured MySQL source. It never
// prints credentials, hostnames, database names, or row payloads.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const serverRoot = path.resolve(process.env.ERP_SERVER_ROOT || "../erp/erp_new/server");
const output = path.resolve(process.argv[2] || "/tmp/moonproj-erp-mysql-inventory.json");
const require = createRequire(import.meta.url);

function safeTable(table) {
  if (!/^[A-Za-z0-9_]+$/.test(table)) throw new Error("unsafe table name");
  return `\`${table}\``;
}

async function main() {
  const dotenv = require(path.join(serverRoot, "node_modules/dotenv"));
  dotenv.config({ path: path.join(serverRoot, ".env"), quiet: true });
  const mysql = require(path.join(serverRoot, "node_modules/mysql2/promise.js"));
  const pool = mysql.createPool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    waitForConnections: true,
    connectionLimit: 2,
    connectTimeout: 10000,
  });
  try {
    const [tableRows] = await pool.query("SHOW TABLES");
    const tableKey = Object.keys(tableRows[0] || {})[0];
    if (!tableKey) throw new Error("source returned no table metadata");
    const tables = [];
    for (const row of tableRows) {
      const table = String(row[tableKey]);
      const quoted = safeTable(table);
      const [counts] = await pool.query(`SELECT COUNT(*) AS rows FROM ${quoted}`);
      const [keys] = await pool.query(`SHOW KEYS FROM ${quoted} WHERE Key_name = 'PRIMARY' ORDER BY Seq_in_index`);
      tables.push({
        table,
        rows: Number(counts[0]?.rows || 0),
        primary_key: keys.map((key) => String(key.Column_name)),
      });
    }
    const report = {
      format: "moonproj.erp.mysql.inventory.v1",
      state: "read_only_metadata_verified",
      source_kind: "mysql",
      table_count: tables.length,
      tables: tables.sort((a, b) => a.table.localeCompare(b.table)),
      rows_read: false,
      credentials_emitted: false,
    };
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    process.stdout.write(JSON.stringify({
      output,
      state: report.state,
      table_count: report.table_count,
      rows_read: report.rows_read,
      credentials_emitted: report.credentials_emitted,
    }) + "\n");
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  const code = typeof error?.code === "string" ? error.code : "metadata_probe_failed";
  process.stderr.write(`ERP MySQL metadata probe failed: ${code}\n`);
  process.exitCode = 1;
});
