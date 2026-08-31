CREATE TABLE items (
    sku           text PRIMARY KEY,
    name          text NOT NULL,
    stock         integer NOT NULL,
    reorder_point integer NOT NULL,
    price         numeric(10,2) NOT NULL
);
INSERT INTO items (sku, name, stock, reorder_point, price) VALUES
  ('CW-201', 'Dried Apricots',        18,  5, 7.25),
  ('CW-202', 'Candied Ginger',         3, 11, 9.90),
  ('CW-203', 'Preserved Lemons',      12, 12, 6.60),
  ('CW-204', 'Rosewater',              5,  5, 4.15),
  ('CW-205', 'Orange Blossom Water',   1,  4, 5.05),
  ('CW-206', 'Fig Vinegar',           22,  8, 3.75);
