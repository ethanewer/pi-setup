CREATE TABLE items (
    sku           text PRIMARY KEY,
    name          text NOT NULL,
    stock         integer NOT NULL,
    reorder_point integer NOT NULL,
    price         numeric(10,2) NOT NULL
);
INSERT INTO items (sku, name, stock, reorder_point, price) VALUES
  ('EM-301', 'Smoked Paprika',    30, 10,  4.40),
  ('EM-302', 'Birch Syrup',       12, 12, 11.00),
  ('EM-303', 'Wild Thyme Honey',   9,  4, 13.25);
