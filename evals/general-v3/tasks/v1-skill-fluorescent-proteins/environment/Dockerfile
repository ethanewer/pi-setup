FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
rows = [
    ("mCherry", 610),
    ("GFP", 509),
    ("mKO", 559),
    ("Cerulean", 432),
    ("tdTomato", 582),
    ("mPlum", 646),
    ("Citrine", 549),
]
with open('/app/proteins.csv','w') as f:
    f.write("name,peak_emission\n")
    for n, p in rows:
        f.write(f"{n},{p}\n")
with open('/app/query.txt','w') as f:
    f.write("600\n")
PY