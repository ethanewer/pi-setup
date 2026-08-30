#!/bin/bash
# Real oracle for basalt-mesa: write the reusable solver, then RUN it on the
# visible fixtures to produce the /app result files. Never reads /tests.
set -eu

cat > /app/solve.py <<'PY'
import json, os, sys
import numpy as np


def recover_edges(X, cols, root, edge_count):
    n = len(cols)
    C = np.corrcoef(X, rowvar=False)
    in_tree = [0]
    edges = []
    rest = [i for i in range(n) if i != 0]
    while rest:
        best = None
        for i in in_tree:
            for j in rest:
                key = (-abs(C[i, j]), min(i, j), max(i, j))
                if best is None or key < best[0]:
                    best = (key, i, j)
        _, i, j = best
        edges.append((i, j))
        in_tree.append(j)
        rest.remove(j)
    children = {i: [] for i in range(n)}
    for (i, j) in edges:
        children[i].append(j)
        children[j].append(i)
    ri = cols.index(root)
    seen = {ri}
    out = []
    queue = [ri]
    while queue:
        u = queue.pop(0)
        for v in children[u]:
            if v not in seen:
                seen.add(v)
                out.append((u, v))
                queue.append(v)
    return out


def main():
    obs_path, dag_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    dag = json.load(open(dag_path))
    cols = dag['network_columns']
    root = dag['root']
    edge_count = dag['edge_count']
    raw = np.genfromtxt(obs_path, delimiter=',', names=True)
    X = np.vstack([raw[c] for c in cols]).T
    os.makedirs(outdir, exist_ok=True)
    edges = recover_edges(X, cols, root, edge_count)
    with open(os.path.join(outdir, 'recovered_edges.csv'), 'w') as f:
        f.write('parent,child\n')
        for (i, j) in edges:
            f.write('%s,%s\n' % (cols[i], cols[j]))
    with open(os.path.join(outdir, 'network_fit.csv'), 'w') as f:
        f.write('parent,child,intercept,slope,sigma\n')
        for (i, j) in edges:
            p, c = X[:, i], X[:, j]
            slope = np.cov(p, c, ddof=0)[0, 1] / np.var(p)
            inter = c.mean() - slope * p.mean()
            resid = c - (inter + slope * p)
            sigma = np.sqrt(np.mean(resid ** 2))
            f.write('%s,%s,%.9f,%.9f,%.9f\n' % (cols[i], cols[j], inter, slope, sigma))
    ri = cols.index(root)
    with open(os.path.join(outdir, 'root_fit.csv'), 'w') as f:
        f.write('node,mu,sigma\n')
        f.write('%s,%.9f,%.9f\n' % (root, X[:, ri].mean(), X[:, ri].std()))
    print('SOLVER_OK')


main()
PY

chmod +x /app/solve.py
python3 /app/solve.py /app/obs.csv /app/dag.json /app
echo "solve.sh done"
ls -l /app/solve.py /app/recovered_edges.csv /app/network_fit.csv /app/root_fit.csv
