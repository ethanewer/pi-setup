FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN python3 -c "import json; m=json.load(open('/app/model/lexicon.json')); assert m['dim']==4 and m['ctx']==3 and m['max_new']==6; print('lexicon-ok')"
