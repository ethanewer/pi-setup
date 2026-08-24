# Distributed collectives: gossip average consensus

Four distributed processes each hold a local number; there is no central
coordinator. The goal of the system is **average consensus**: the processes
repeatedly exchange and update values so that, after enough rounds, every
process holds the same value — the global average of all initial values.

`/app/processes.txt` contains the four initial values, one per line (integers):

```
10
20
30
40
```

## Task

Write a Python 3 script `/app/gossip.py` that simulates **deterministic
pairwise-averaging gossip** on a ring and writes the final values to
`/app/final.txt`.

### Simulation rules

- Number of processes `N = 4`, indexed `0..3` around a ring. Process `i`'s
  neighbor is `(i + 1) % N`.
- Run exactly `R = 40` rounds. In every round, apply the update to all four
  processes **synchronously**:
  `v[i] = (v[i] + v[(i+1) % N]) / 2`.
  (Each process replaces its value with the average of its own value and its
  neighbor's value. This is the classic sum-preserving gossip averaging step.)
- Start with the values read from `/app/processes.txt` (in file order, index 0
  = first line).

### Output

Write `/app/final.txt` with the four values after round 40, one per line in
index order. Format each value with `repr()` of a Python float (e.g.
`25.0`).

After enough rounds of connected averaging, all four values must converge to
the global mean, which for this input is `25.0` — your final four lines should
all be (essentially) `25.0`.

The verifier checks that every line of `/app/final.txt` is within `1e-3` of the
true global average (`(10+20+30+40)/4`).