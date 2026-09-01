FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
import json
heap = {
    "roots": ["a"],
    "objects": {
        "a": ["b", "c"],
        "b": ["d"],
        "c": [],
        "d": ["a"],
        "e": ["f"],
        "f": ["g"],
        "g": [],
        "h": []
    }
}
with open('/app/heap.json','w') as f:
    json.dump(heap, f)
PY