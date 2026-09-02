SELECT sku FROM shipments WHERE batch = 'seed';
SELECT sku, qty, destination FROM shipments WHERE batch = 'wal-committed';