SELECT region, status, channel, COUNT(*) AS n, SUM(total) AS revenue
FROM order_facts
GROUP BY region, status, channel
ORDER BY region, status, channel