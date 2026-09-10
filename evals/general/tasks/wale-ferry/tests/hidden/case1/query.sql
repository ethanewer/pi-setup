SELECT region, status, COUNT(*) AS n, SUM(total) AS revenue
FROM order_facts
WHERE status IN ('confirmed','delivered')
  AND placed_at >= '2025-01-01' AND placed_at < '2025-10-01'
GROUP BY region, status
HAVING n > 4000
ORDER BY region, status