-- Meridian Freight warehouse -- backward migration.
-- Removes exactly the structures forward added; leaves every row untouched.
DROP INDEX events_monthly_idx;
DROP INDEX journeys_monthly_idx;