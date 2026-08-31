#!/usr/bin/env python3
"""Generate the 1.2M-patch stress trace set at verify time (deterministic).

Writes <out> (default /tmp/stress_traces.csv): 3 traces, 1,200,000 patches,
same CSV format as the visible/hidden inputs.
"""
import sys

import numpy as np
import pandas as pd

np.seterr(all="ignore")
F = 32
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/stress_traces.csv"

rng = np.random.default_rng(99)
frames = []
for tid, n, sh in [("s-big", 1_000_000, 0.9), ("s-mid", 150_000, -0.7),
                   ("s-small", 50_000, 0.2)]:
    X = rng.normal(0, 1.0, (n, F)) + sh
    df = pd.DataFrame(X, columns=[f"x{i}" for i in range(F)])
    df.insert(0, "trace_id", tid)
    frames.append(df)
pd.concat(frames, ignore_index=True).to_csv(OUT, index=False,
                                            float_format="%.6f")
print("wrote", OUT)
