# JSON weight conversion

`/app/items.json` is a JSON array of objects. Each object is:

```json
{"name": "<string>", "weight": <number>, "unit": "<kg|g|lb|oz>"}
```

Convert every weight to **kilograms** and write a new JSON array to `/app/normalized.json` where each element is:

```json
{"name": "<same name>", "weight_kg": <number>}
```

Conversion factors (exact):
- `1 g  = 0.001 kg`
- `1 oz = 0.028349523125 kg`
- `1 lb = 0.45359237 kg`
- `kg` values pass through unchanged.

Round each `weight_kg` to 6 decimal places using standard rounding (Python's `round(x, 6)`). Keep the original array order.

Example:

```python
import json
items = json.load(open('/app/items.json'))
factors = {"kg": 1.0, "g": 0.001, "oz": 0.028349523125, "lb": 0.45359237}
out = [{"name": it["name"], "weight_kg": round(it["weight"] * factors[it["unit"]], 6)} for it in items]
json.dump(out, open('/app/normalized.json', 'w'), indent=2)
```

Afterward `/app/normalized.json` must be valid JSON containing the normalized array.