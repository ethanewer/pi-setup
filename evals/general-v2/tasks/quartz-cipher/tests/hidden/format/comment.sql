-- a comment line makes this file invalid (must be rejected)
SELECT sku, qty, destination
FROM shipments
WHERE batch = 'wal-committed';