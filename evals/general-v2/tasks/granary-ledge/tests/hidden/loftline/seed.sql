CREATE TABLE items (
    sku           text PRIMARY KEY,
    name          text NOT NULL,
    stock         integer NOT NULL,
    reorder_point integer NOT NULL,
    price         numeric(10,2) NOT NULL
);
INSERT INTO items (sku, name, stock, reorder_point, price) VALUES
  ('LF-401', 'Rye Crispbread',    7, 20, 2.99),
  ('LF-402', 'Juniper Berries',  15,  6, 5.50),
  ('LF-403', 'Bay Leaves',        0,  3, 1.25),
  ('LF-404', 'Malt Extract',     44, 12, 6.10);
