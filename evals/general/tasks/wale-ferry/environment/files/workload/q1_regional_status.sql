SELECT region, status, COUNT(*) AS n, COALESCE(SUM(total),0) AS revenue
FROM order_facts
GROUP BY region, status
ORDER BY region, status