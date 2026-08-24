# Layer / coordinate interpretation

Two files define a set of non-overlapping depth layers and a set of sample depths:

- `/app/layers.json`: `{"layers": [ {"name": "<s>", "min": <n>, "max": <n>}, ... ]}` — the layers are sorted and contiguous.
- `/app/depths.csv`: a single line with comma-separated depth values.

Assign every depth to the layer whose **inclusive lower bound and exclusive upper bound** cover it: a depth `d` belongs to a layer iff `min <= d < max`.

Write `/app/assignments.json` as a JSON object mapping each depth string to the layer **name**:

```json
{"0": "light", "5": "light", "10": "mid", ...}
```

Keys must be the depths formatted as decimal integers (as they appear numerically, e.g. `"10"`), and each depth from the CSV must appear.

Implementation hint:

```python
import json
layers = json.load(open('/app/layers.json'))['layers']
depths = [float(x) for x in open('/app/depths.csv').read().strip().split(',')]
mapping = {}
for d in depths:
    for L in layers:
        if L['min'] <= d < L['max']:
            mapping[str(int(d))] = L['name']
            break
json.dump(mapping, open('/app/assignments.json', 'w'))
```

Afterward `/app/assignments.json` must be valid JSON with the correct layer name for every depth.