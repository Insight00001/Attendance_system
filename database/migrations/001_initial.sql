-- Migration 001 — Initial schema
-- Applied automatically when PostgreSQL container starts
-- (Handled by docker-entrypoint-initdb.d/01_schema.sql → see schema.sql)

-- This file serves as a record of the initial migration.
-- For subsequent migrations, add numbered files:
--   002_add_leave_table.sql
--   003_add_biometric_column.sql
-- and apply with:
--   psql -U $POSTGRES_USER -d $POSTGRES_DB -f database/migrations/002_add_leave_table.sql

SELECT 'Migration 001 (initial) — applied via schema.sql' AS status;
