FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
import json
with open('/app/model.json','w') as f:
    json.dump({"w": 2.0, "b": 1.0}, f)
with open('/app/data.json','w') as f:
    json.dump({"x": [1.0,2.0,3.0,4.0], "y": [3.5,4.0,7.5,8.5]}, f)
PY