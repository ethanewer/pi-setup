SELECT region, status, COUNT(*) AS n, SUM(total) AS revenue
FROM order_facts
WHERE channel = 'online'
GROUP BY region, status
ORDER BY region, status