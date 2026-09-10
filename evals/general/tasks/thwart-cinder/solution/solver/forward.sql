-- Meridian Freight warehouse -- forward migration.
-- Adds the access structures the monthly analytical reports need, without
-- touching any row, column, constraint or table.
CREATE INDEX events_monthly_idx ON events (tenant_id, occurred_at);
CREATE INDEX journeys_monthly_idx ON journeys (tenant_id, occurred_at);