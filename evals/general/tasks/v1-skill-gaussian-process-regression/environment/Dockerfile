FROM bench-base:python-3.12

WORKDIR /app

RUN pip install numpy

RUN python3 - <<'PY'
import json
json.dump([-2.0,-1.0,0.0,1.0,2.0,3.0], open('/app/xtrain.json','w'))
json.dump([4.5,0.5,1.5,0.5,4.5,22.0], open('/app/ytrain.json','w'))
json.dump([0.5,1.5,2.5], open('/app/xtest.json','w'))
PY