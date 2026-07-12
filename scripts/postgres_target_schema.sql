CREATE TABLE IF NOT EXISTS company_schema (
  version INTEGER NOT NULL PRIMARY KEY,
  checksum VARCHAR(255) NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS company_record (
  record_type VARCHAR(128) NOT NULL,
  record_id VARCHAR(255) NOT NULL,
  schema_version INTEGER NOT NULL,
  payload JSONB NOT NULL,
  source_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (record_type, record_id),
  UNIQUE (source_id)
);
CREATE INDEX IF NOT EXISTS company_record_source_idx ON company_record(source_id);

CREATE TABLE IF NOT EXISTS company_aggregate_projection (
  aggregate_type VARCHAR(128) NOT NULL,
  aggregate_id VARCHAR(255) NOT NULL,
  revision INTEGER NOT NULL,
  payload JSONB NOT NULL,
  source_event_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (aggregate_type, aggregate_id, revision),
  UNIQUE (aggregate_type, aggregate_id, source_event_id)
);
CREATE INDEX IF NOT EXISTS company_projection_event_idx
  ON company_aggregate_projection(source_event_id);

CREATE TABLE IF NOT EXISTS company_accounting_event_link (
  event_id VARCHAR(255) NOT NULL PRIMARY KEY,
  source_type VARCHAR(128) NOT NULL,
  source_id VARCHAR(255) NOT NULL,
  journal_id VARCHAR(255) NOT NULL,
  principal_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (source_type, source_id),
  UNIQUE (journal_id)
);
CREATE INDEX IF NOT EXISTS company_accounting_source_idx
  ON company_accounting_event_link(source_type, source_id);

CREATE TABLE IF NOT EXISTS company_migration_receipt (
  run_id VARCHAR(255) NOT NULL PRIMARY KEY,
  source_snapshot_id VARCHAR(255) NOT NULL,
  target_schema_version INTEGER NOT NULL,
  mapping_version VARCHAR(255) NOT NULL,
  state VARCHAR(32) NOT NULL,
  baseline_hash VARCHAR(255) NOT NULL,
  applied_hash VARCHAR(255) NOT NULL,
  certified_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS company_receipt_snapshot_idx
  ON company_migration_receipt(source_snapshot_id);

INSERT INTO company_schema(version, checksum)
VALUES
  (1, 'sha256:company-record-envelope-v1'),
  (2, 'sha256:aggregate-projection-v1'),
  (3, 'sha256:accounting-event-link-v1'),
  (4, 'sha256:moonproj-postgresql-company-catalog-v4')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      (1, 'sha256:company-record-envelope-v1'),
      (2, 'sha256:aggregate-projection-v1'),
      (3, 'sha256:accounting-event-link-v1'),
      (4, 'sha256:moonproj-postgresql-company-catalog-v4')
    ) AS expected(version, checksum)
    JOIN company_schema actual USING (version)
    WHERE actual.checksum <> expected.checksum
  ) THEN
    RAISE EXCEPTION 'company schema checksum mismatch';
  END IF;
END $$;
