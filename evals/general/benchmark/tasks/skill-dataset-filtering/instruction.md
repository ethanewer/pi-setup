At `/app/dataset.json` there is a JSON array of product records. Each record has the shape:

```json
{"product_id": "...", "category": "...", "price": <number>, "in_stock": <boolean>}
```

Write `/app/filter.py` that:
1. loads `/app/dataset.json`,
2. keeps only the records that satisfy **all three** conditions:
   - `in_stock` is `true`,
   - `price` is less than or equal to `50.0`,
   - `category` is **not** `"food"`,
3. writes the filtered array (in the same order as the input) to `/app/filtered.json`.

The expected result number of records is 3 (product ids `p1`, `p2`, `p5`; product `p3` is too expensive, `p4` is out of stock, and `p6` is food). Use only the Python standard library. Run your script so `/app/filtered.json` exists.
