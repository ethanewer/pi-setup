#!/bin/bash
# Oracle for onyx-relay: author the compact engine, then RUN it on the visible
# fixtures to produce /app/preds.csv. Never reads /tests.
set -eu

ENGINE="/app/engine.py"
OUT="/app/preds.csv"

cat > "$ENGINE" <<'PY'
import json, sys, math

def ln(X, g, b):
    o = []
    for v in X:
        n = len(v); m = sum(v)/n
        var = sum((x-m)*(x-m) for x in v)/n
        dd = math.sqrt(var+1e-5)
        o.append([(x-m)/dd*g[j]+b[j] for j, x in enumerate(v)])
    return o

def mm(a, w):
    return [[sum(r[t]*w[t][j] for t in range(len(w))) for j in range(len(w[0]))] for r in a]

def fwd(S, C, toks):
    d = C["d"]; dh = d//C["heads"]; V = C["vocab"]; T = len(toks)
    x = [[S["embed"][t][j] + S["pos"][i][j] for j in range(d)] for i, t in enumerate(toks)]
    for L in range(C["layers"]):
        n1 = mm(ln(x, S["ln1g%d" % L], S["ln1b%d" % L]), S["qkv%d" % L])
        q = [r[0:d] for r in n1]; k = [r[d:2*d] for r in n1]; v = [r[2*d:] for r in n1]
        ctx = [[0.0]*d for _ in range(T)]
        for h in range(C["heads"]):
            a, b = h*dh, (h+1)*dh
            for i in range(T):
                sc = [sum(q[i][t]*k[j][t] for t in range(a, b))/math.sqrt(dh) for j in range(i+1)]
                mx = max(sc); ex = [math.exp(s-mx) for s in sc]; Z = sum(ex)
                for j in range(i+1):
                    w = ex[j]/Z
                    for t in range(a, b): ctx[i][t] += w*v[j][t]
        o = mm(ctx, S["o%d" % L])
        x = [[x[i][j]+o[i][j] for j in range(d)] for i in range(T)]
        f = mm(ln(x, S["ln2g%d" % L], S["ln2b%d" % L]), S["w1%d" % L])
        f = [[z/(1.0+math.exp(-z)) for z in r] for r in f]
        f = mm(f, S["w2%d" % L])
        x = [[x[i][j]+f[i][j] for j in range(d)] for i in range(T)]
    z = ln(x[T-1:], S["lfg"], S["lfb"])[0]
    lg = [sum(z[j]*S["head"][j][vi] for j in range(d)) for vi in range(V)]
    bi = max(range(V), key=lg.__getitem__)
    return bi, lg[bi]

def main():
    a = sys.argv[1:]
    cfg, st, da = a[0], a[1], a[2]
    out = a[a.index("--out")+1] if "--out" in a else "preds.csv"
    C = json.load(open(cfg)); S = json.load(open(st)); D = json.load(open(da))
    rows = ["sid,token,logit"]
    for sid, toks in D:
        bi, lg = fwd(S, C, toks)
        rows.append("%s,%d,%.6f" % (sid, bi, lg))
    open(out, "w").write("\n".join(rows) + "\n")

main()
PY

chmod +x "$ENGINE"
python3 -m py_compile "$ENGINE"
echo "engine.py bytes: $(wc -c < "$ENGINE") (cap 5000)"

python3 "$ENGINE" /app/fixtures/config.json /app/fixtures/state.json /app/fixtures/data.json --out "$OUT"
echo "solve.sh done -> $ENGINE and $OUT"
ls -l "$ENGINE" "$OUT"
