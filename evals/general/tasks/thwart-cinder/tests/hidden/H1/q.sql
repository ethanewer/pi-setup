-- Hidden case H1: monthly cost report -- tenant 61, November 2025.
SELECT to_char(date_trunc('month', occurred_at), 'YYYY-MM') AS month,
       region,
       sum(amount) AS revenue
FROM events
WHERE tenant_id = 61
  AND occurred_at >= '2025-11-01 00:00:00'
  AND occurred_at <  '2025-12-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1, 2;