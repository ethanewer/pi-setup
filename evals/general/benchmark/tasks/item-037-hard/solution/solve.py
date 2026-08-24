#!/usr/bin/env python3
import json
import numpy as np

data = json.load(open('/app/matrix.json'))
A = np.array([[complex(r['re'], r['im']) for r in row] for row in data])
ev, V = np.linalg.eig(A)
# normalize columns to unit norm
V = V / np.linalg.norm(V, axis=0, keepdims=True)

def c2j(z):
    return {'re': round(z.real, 12), 'im': round(z.imag, 12)}

out = {
    'eigenvalues': [c2j(ev[i]) for i in range(6)],
    'eigenvectors': [[c2j(V[i, j]) for i in range(6)] for j in range(6)],
}
json.dump(out, open('/app/eig.json', 'w'), indent=2)
print('eigenvalues:', [str(round(ev[i], 8)) for i in range(6)])