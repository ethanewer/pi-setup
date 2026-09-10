-- Keel & Co. fulfillment analytics schema (authoritative DDL).
-- The live database in the `analytics` schema is seeded identically to this
-- file, plus the dependent reporting view `vw_region_performance`.
CREATE DATABASE IF NOT EXISTS analytics CHARACTER SET utf8mb4;
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
  KEY idx_order_facts_customer (customer_id),
  KEY idx_order_facts_status  (status)
) ENGINE=InnoDB;

CREATE OR REPLACE VIEW vw_region_performance AS
SELECT
  region,
  COUNT(*)                       AS orders,
  COALESCE(SUM(total), 0)        AS revenue,
  ROUND(AVG(total), 2)           AS avg_total
FROM order_facts
GROUP BY region;