FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
records = [(1,"Alice",30,"New York"),(2,"Bob",35,"Boston"),(3,"Carol",42,"London")]
with open('/app/people.dat','w') as f:
    for i,n,a,c in records:
        f.write(f"{i:0>4}{n:<12}{a:>3}{c}\n")
PY