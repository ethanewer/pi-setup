-- wale-ferry pristine seed. Rebuilds the analytics database from scratch so
-- that `dbctl.sh reset` restores an unobserved, fully deterministic state for
-- the verifier. The data is loaded from the byte-identical TSV generated at
-- image build time, so every reset reproduces the golden result files.
DROP DATABASE IF EXISTS analytics;
CREATE DATABASE analytics CHARACTER SET utf8mb4;
USE analytics;

CREATE TABLE order_facts (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  customer_id INT UNSIGNED NOT NULL,
  region      VARCHAR(16)   NOT NULL,
  channel     VARCHAR(12)   NOT NULL,
  status      VARCHAR(12)   NOT NULL,
  placed_at   DATETIME      NOT NULL,
  total       DECIMAL(10,2) NOT NULL,
  items       SMALLINT UNSIGNED NOT NULL,
  -- Historical, transaction-shaped indexes (FK lookups, status filters).
  KEY idx_order_facts_customer (customer_id),
  KEY idx_order_facts_status  (status)
) ENGINE=InnoDB;

LOAD DATA INFILE '/opt/warehouse/order_facts.tsv'
  INTO TABLE order_facts
  (customer_id, region, channel, status, placed_at, total, items);

-- Collect stable statistics so EXPLAIN plans are deterministic right after
-- a fresh start rather than depending on in-flight stat sampling.
ANALYZE TABLE order_facts;

-- Dependent reporting view: the regional rollup the ops team reads weekly.
CREATE OR REPLACE VIEW vw_region_performance AS
SELECT
  region,
  COUNT(*)                       AS orders,
  COALESCE(SUM(total), 0)        AS revenue,
  ROUND(AVG(total), 2)           AS avg_total
FROM order_facts
GROUP BY region;

-- Convenience login for TCP work; the socket root login is preferred.
CREATE USER IF NOT EXISTS 'analyst'@'localhost' IDENTIFIED BY 'Dock-Side-Pass-2206';
CREATE USER IF NOT EXISTS 'analyst'@'127.0.0.1' IDENTIFIED BY 'Dock-Side-Pass-2206';
GRANT ALL PRIVILEGES ON analytics.* TO 'analyst'@'localhost';
GRANT ALL PRIVILEGES ON analytics.* TO 'analyst'@'127.0.0.1';
FLUSH PRIVILEGES;