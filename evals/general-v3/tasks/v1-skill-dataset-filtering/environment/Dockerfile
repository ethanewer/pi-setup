FROM bench-base:python-3.12

WORKDIR /app

# A small product dataset to filter.
RUN cat > /app/dataset.json <<'JSON'
[
  {"product_id": "p1", "category": "electronics", "price": 49.99, "in_stock": true},
  {"product_id": "p2", "category": "clothing", "price": 10.00, "in_stock": true},
  {"product_id": "p3", "category": "electronics", "price": 129.50, "in_stock": true},
  {"product_id": "p4", "category": "food", "price": 3.50, "in_stock": false},
  {"product_id": "p5", "category": "clothing", "price": 4.25, "in_stock": true},
  {"product_id": "p6", "category": "food", "price": 8.75, "in_stock": true}
]
JSON
