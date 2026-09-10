-- Meridian Freight: monthly service-cost report -- tenant 17, June 2025.
-- Current production query (original.sql). Correct, but slow: it grows
-- slower every month as the warehouse accumulates rows.
SELECT to_char(date_trunc('month', occurred_at), 'YYYY-MM') AS month,
       kind,
       sum(amount) AS revenue
FROM events
WHERE tenant_id = 17
  AND to_char(occurred_at, 'YYYY-MM') = '2025-06'
GROUP BY 1, 2
ORDER BY 1, 2;