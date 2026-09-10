SELECT region, status, COUNT(*) AS n, SUM(total) AS revenue
FROM order_facts
WHERE placed_at >= '2025-01-01' AND placed_at < '2025-07-01'
GROUP BY region, status
ORDER BY region, status