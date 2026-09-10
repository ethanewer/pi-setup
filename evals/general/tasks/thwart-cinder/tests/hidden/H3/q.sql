-- Hidden case H3: monthly cost report -- tenant 17, January 2026.
SELECT to_char(date_trunc('month', occurred_at), 'YYYY-MM') AS month,
       kind,
       sum(amount) AS revenue
FROM events
WHERE tenant_id = 17
  AND occurred_at >= '2026-01-01 00:00:00'
  AND occurred_at <  '2026-02-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1, 2;