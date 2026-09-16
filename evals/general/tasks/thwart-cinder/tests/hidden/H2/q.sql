-- Hidden case H2: monthly distance report -- tenant 34, September 2025.
SELECT to_char(date_trunc('month', occurred_at), 'YYYY-MM') AS month,
       kind,
       sum(distance_km) AS kilometres
FROM journeys
WHERE tenant_id = 34
  AND occurred_at >= '2025-09-01 00:00:00'
  AND occurred_at <  '2025-10-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1, 2;