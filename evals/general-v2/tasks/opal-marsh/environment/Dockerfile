FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN python3 -c "import json; s=json.load(open('/app/spec.json')); assert s['bits']==8 and s['a']==156 and s['r']==3; print('spec-ok')"
