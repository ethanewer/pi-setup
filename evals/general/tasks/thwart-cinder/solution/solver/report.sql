-- Meridian Freight: monthly service-cost report -- tenant 17, June 2025.
-- Rewritten form: same rows as original.sql, but the time window is a range
-- predicate on occurred_at, which the optimizer can resolve through an index.
SELECT to_char(date_trunc('month', occurred_at), 'YYYY-MM') AS month,
       kind,
       sum(amount) AS revenue
FROM events
WHERE tenant_id = 17
  AND occurred_at >= '2025-06-01 00:00:00'
  AND occurred_at <  '2025-07-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1, 2;