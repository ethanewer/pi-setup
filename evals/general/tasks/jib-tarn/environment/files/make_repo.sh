#!/usr/bin/env bash
# Builds the synthetic `sundial` repository at /app/repo with exactly 25
# commits on `main`. Commit 16 (index 15, message "perf: replace deque
# bookkeeping with slice maxima for cache locality") intentionally introduces
# an accidental O(n^2) hot path in src/sundial/window.py: the sliding-window
# maximum is computed with `max(data[i:i+k])` per window instead of a
# monotonic deque. Every commit keeps the correctness test-suite green; only
# the time complexity of the hot path changes.
#
# The author/committer timestamps are pinned so the 25 commit hashes are
# deterministic across rebuilds. The verifier asserts the regression commit's
# hash is present in history.
set -euo pipefail

REPO=/app/repo
rm -rf "$REPO"
mkdir -p "$REPO"
cd "$REPO"

git init -q -b main
git config user.email build@localhost
git config user.name build
git config commit.gpgsign false

export GIT_AUTHOR_NAME=build
export GIT_AUTHOR_EMAIL=build@localhost
export GIT_COMMITTER_NAME=build
export GIT_COMMITTER_EMAIL=build@localhost

STEP=0
commit() { # $1 = commit message; stages are already added
  local d
  d=$(date -u -d "2025-01-06T08:00:00 +0000 + $((STEP)) minutes" "+%Y-%m-%dT%H:%M:%S")
  STEP=$((STEP + 1))
  GIT_AUTHOR_DATE="$d +0000" GIT_COMMITTER_DATE="$d +0000" git commit -q -m "$1"
}

# ---------------------------------------------------------------------------
# 1. scaffold
# ---------------------------------------------------------------------------
mkdir -p src/sundial
cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=64", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "sundial"
version = "0.1.0"
description = "Windowed analytics over event series"
readme = "README.md"
requires-python = ">=3.9"

[tool.setuptools.packages.find]
where = ["src"]
EOF
cat > .gitignore <<'EOF'
__pycache__/
*.py[cod]
.pytest_cache/
*.egg-info/
build/
dist/
EOF
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2025 sundial contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and to sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

The Software is provided "as-is", without warranty of any kind, express or
implied, including but not limited to the warranties of merchantability,
fitness for a particular purpose and non-infringement. In no event shall the
authors or copyright holders be liable for any claim, damages or other
liability, whether in an action of contract, tort or otherwise, arising from,
out of or in connection with the Software or from other dealings in the
Software.
EOF
cat > src/sundial/__init__.py <<'EOF'
"""sundial: windowed analytics over event series."""

__version__ = "0.1.0"
EOF
cat > README.md <<'EOF'
# sundial

Windowed analytics over event series: sliding-window maxima, spike detection
and CSV persistence. Work in progress.
EOF
git add -A
commit "chore: scaffold sundial package and packaging metadata"

# ---------------------------------------------------------------------------
# 2. sliding-window maximum (linear, monotonic deque)
# ---------------------------------------------------------------------------
cat > src/sundial/window.py <<'EOF'
"""Windowed operations over event series.

The public entry point is :func:`slide`, which computes the maximum of every
contiguous window of a fixed size in linear time using a monotonic deque of
indices.
"""

from collections import deque
from typing import List, Sequence

__all__ = ["slide"]


def slide(data: Sequence[int], size: int) -> List[int]:
    """Return the maximum of every contiguous window of ``size`` values.

    ``data`` holds non-negative integers (event magnitudes); ``size`` must be
    at least 1 (smaller values are clamped to 1).  Windows are scanned left to
    right: for a series of length *n* the result has ``n - size + 1`` entries.
    When ``size`` exceeds the series length (or the series is empty) the
    result is empty.
    """
    k = max(1, size)
    n = len(data)
    if n == 0 or k > n:
        return []
    out = [0] * (n - k + 1)
    dq: deque = deque()
    for j, x in enumerate(data):
        while dq and data[dq[-1]] <= x:
            dq.pop()
        dq.append(j)
        if dq[0] <= j - k:
            dq.popleft()
        if j >= k - 1:
            out[j - k + 1] = data[dq[0]]
    return out
EOF
git add -A
commit "feat: sliding-window maximum in window.slide (monotonic deque)"

# ---------------------------------------------------------------------------
# 3. descriptive statistics
# ---------------------------------------------------------------------------
cat > src/sundial/metrics.py <<'EOF'
"""Basic descriptive statistics for event series."""

import math
from typing import List, Sequence

__all__ = ["mean", "stdev"]


def mean(values: Sequence[float]) -> float:
    """Arithmetic mean; raises ValueError for an empty series."""
    if not values:
        raise ValueError("mean of an empty series is undefined")
    return sum(values) / len(values)


def stdev(values: Sequence[float]) -> float:
    """Sample standard deviation (n-1 denominator)."""
    if len(values) < 2:
        raise ValueError("sample standard deviation needs at least two values")
    m = mean(values)
    return math.sqrt(sum((v - m) ** 2 for v in values) / (len(values) - 1))
EOF
git add -A
commit "feat: basic descriptive statistics module"

# ---------------------------------------------------------------------------
# 4. spike detection
# ---------------------------------------------------------------------------
cat > src/sundial/outliers.py <<'EOF'
"""Anomaly detection helpers built on window operations."""

from typing import List, Sequence

from .metrics import mean, stdev
from .window import slide

__all__ = ["detect_spikes"]


def detect_spikes(
    data: Sequence[int], size: int, z: float = 3.0
) -> List[int]:
    """Return the right-edge indices of windows whose maximum stands out.

    Each window maximum is compared against ``mean(maxima) + z * stdev`` of
    all window maxima.  Indices are positions in ``data`` (the right edge of
    the offending window).  Series too short to open a single window produce
    no spike flags.
    """
    maxima = slide(data, size)
    if len(maxima) < 2:
        return []
    m = mean(maxima)
    s = stdev(maxima)
    if s == 0:
        return []
    cutoff = m + z * s
    return [i + max(1, size) - 1 for i, v in enumerate(maxima) if v > cutoff]
EOF
git add -A
commit "feat: spike detection over window maxima"

# ---------------------------------------------------------------------------
# 5. CSV persistence
# ---------------------------------------------------------------------------
cat > src/sundial/io.py <<'EOF'
"""CSV persistence for event series."""

import csv
from pathlib import Path
from typing import List

__all__ = ["read_series", "write_series"]


def read_series(path) -> List[int]:
    """Read a one-column CSV of integers; non-numeric rows are skipped."""
    with open(path, newline="", encoding="utf-8") as fh:
        out = []
        for row in csv.reader(fh):
            if not row:
                continue
            try:
                out.append(int(row[0].strip()))
            except ValueError:
                continue
        return out


def write_series(path, series: List[int]) -> None:
    """Write a one-column CSV with a ``value`` header row."""
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["value"])
        for value in series:
            writer.writerow([value])
EOF
git add -A
commit "feat: CSV persistence for event series"

# ---------------------------------------------------------------------------
# 6. window tests
# ---------------------------------------------------------------------------
mkdir -p tests
cat > tests/test_window.py <<'EOF'
"""Correctness of sundial.window.slide."""

import pytest

from sundial.window import slide


def test_window_size_one_returns_series():
    data = [3, 1, 4, 1, 5, 9]
    assert slide(data, 1) == data


def test_full_length_window_returns_single_maximum():
    data = [7, 2, 5, 8]
    assert slide(data, len(data)) == [8]


def test_window_larger_than_series_is_empty():
    assert slide([1, 2, 3], 10) == []


def test_window_wider_than_series_stays_empty():
    assert slide([1, 2, 3], len([1, 2, 3]) + 4) == []


def test_known_pattern_increasing():
    # Strictly increasing series: each window maximum is its rightmost value.
    data = [1, 3, 5, 7, 9, 11]
    assert slide(data, 3) == [5, 7, 9, 11]


def test_ties_keep_value():
    assert slide([4, 4, 4], 2) == [4, 4]


def test_empty_series_is_empty():
    assert slide([], 3) == []


def test_length_contract():
    n = 12
    data = list(range(n, 0, -1))
    for k in range(1, n + 1):
        out = slide(data, k)
        assert len(out) == n - k + 1
        assert out[0] == max(data[:k])
        assert out[-1] == max(data[-k:])
EOF
git add -A
commit "test: window edge cases and known patterns"

# ---------------------------------------------------------------------------
# 7. metrics tests
# ---------------------------------------------------------------------------
cat > tests/test_metrics.py <<'EOF'
"""Correctness of sundial.metrics."""

import math

import pytest

from sundial.metrics import mean, stdev


def test_mean_of_known_values():
    assert mean([1, 2, 3, 4]) == 2.5


def test_mean_empty_raises():
    with pytest.raises(ValueError):
        mean([])


def test_stdev_of_constant_series_is_zero():
    assert stdev([5, 5, 5, 5]) == 0.0


def test_stdev_matches_manual_formula():
    values = [3, 7, 8, 2, 10]
    m = mean(values)
    expected = math.sqrt(sum((v - m) ** 2 for v in values) / (len(values) - 1))
    assert stdev(values) == pytest.approx(expected)


def test_stdev_short_series_raises():
    with pytest.raises(ValueError):
        stdev([1])
EOF
git add -A
commit "test: metrics correctness"

# ---------------------------------------------------------------------------
# 8. outlier tests
# ---------------------------------------------------------------------------
cat > tests/test_outliers.py <<'EOF'
"""Correctness of sundial.outliers.detect_spikes."""

import pytest

from sundial.outliers import detect_spikes


def test_no_spikes_in_flat_series():
    data = [10] * 40
    assert detect_spikes(data, 8, z=1.5) == []


def test_spike_windows_flagged():
    # One dominant value at index 20: exactly the windows whose maximum is
    # that value are flagged, and they line up on their right edges.
    data = [1] * 20 + [10000] + [1] * 19
    flagged = detect_spikes(data, 4, z=2.0)
    assert flagged == list(range(20, 24))


def test_short_series_no_flags():
    assert detect_spikes([5, 5, 5], 4, z=100.0) == []


def test_zero_spread_flags_nothing():
    assert detect_spikes([4, 4, 4, 4, 4, 4], 3, z=0.0) == []
EOF
git add -A
commit "test: outlier fixtures"

# ---------------------------------------------------------------------------
# 9. README quickstart
# ---------------------------------------------------------------------------
cat > README.md <<'EOF'
# sundial

Windowed analytics over event series: sliding-window maxima, spike detection
and CSV persistence.

## Quickstart

```python
>>> from sundial import slide, detect_spikes
>>> slide([3, 1, 4, 1, 5, 9, 2], 3)
[4, 4, 5, 9, 9]
>>> detect_spikes([2] * 6 + [50] + [2] * 6, 3, z=3.0)
[]
```

Series are stored as one-column CSV files:

```python
>>> from sundial.io import write_series, read_series
>>> write_series("/tmp/events.csv", [1, 2, 3, 2])
>>> read_series("/tmp/events.csv")
[1, 2, 3, 2]
```

## Layout

| Path | Purpose |
|---|---|
| `src/sundial/` | the library |
| `tests/` | correctness suite (`python3 -m pytest -q`) |
| `benchmarks/` | performance harness |
EOF
git add -A
commit "docs: README with quickstart"

# ---------------------------------------------------------------------------
# 10. pytest configuration
# ---------------------------------------------------------------------------
cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=64", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "sundial"
version = "0.1.0"
description = "Windowed analytics over event series"
readme = "README.md"
requires-python = ">=3.9"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
EOF
git add -A
commit "chore: pytest configuration in pyproject"

# ---------------------------------------------------------------------------
# 11. peek CLI
# ---------------------------------------------------------------------------
cat > src/sundial/cli.py <<'EOF'
"""Command-line interface: inspect event series files."""

import argparse
import sys

from . import io
from .window import slide


def peek(path: str, size: int) -> None:
    series = io.read_series(path)
    for i, value in enumerate(slide(series, size)):
        print(f"{i + size - 1}\t{value}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sundial", description="Windowed analytics over event series"
    )
    sub = parser.add_subparsers(dest="command", required=True)
    p_peek = sub.add_parser("peek", help="print window maxima with window end index")
    p_peek.add_argument("path")
    p_peek.add_argument("--size", type=int, default=5)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "peek":
        peek(args.path, args.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOF
git add -A
commit "feat: peek CLI for printing window maxima"

# ---------------------------------------------------------------------------
# 12. share z-score helper
# ---------------------------------------------------------------------------
cat > src/sundial/metrics.py <<'EOF'
"""Basic descriptive statistics for event series."""

import math
from typing import Sequence

__all__ = ["mean", "stdev", "zscore"]


def mean(values: Sequence[float]) -> float:
    """Arithmetic mean; raises ValueError for an empty series."""
    if not values:
        raise ValueError("mean of an empty series is undefined")
    return sum(values) / len(values)


def stdev(values: Sequence[float]) -> float:
    """Sample standard deviation (n-1 denominator)."""
    if len(values) < 2:
        raise ValueError("sample standard deviation needs at least two values")
    m = mean(values)
    return math.sqrt(sum((v - m) ** 2 for v in values) / (len(values) - 1))


def zscore(value: float, m: float, s: float) -> float:
    """Standard score of ``value`` against a precomputed baseline."""
    return (value - m) / s if s != 0.0 else 0.0
EOF
cat > src/sundial/outliers.py <<'EOF'
"""Anomaly detection helpers built on window operations."""

from typing import List, Sequence

from .metrics import mean, stdev, zscore
from .window import slide

__all__ = ["detect_spikes"]


def detect_spikes(
    data: Sequence[int], size: int, z: float = 3.0
) -> List[int]:
    """Return the right-edge indices of windows whose maximum stands out.

    Each window maximum is compared against ``mean(maxima) + z * stdev`` of
    all window maxima.  Indices are positions in ``data`` (the right edge of
    the offending window).  Series too short to open a single window produce
    no spike flags.
    """
    maxima = slide(data, size)
    if len(maxima) < 2:
        return []
    m = mean(maxima)
    s = stdev(maxima)
    if s == 0:
        return []
    cutoff = m + z * s
    return [i + max(1, size) - 1 for i, v in enumerate(maxima) if v > cutoff]
EOF
git add -A
commit "refactor: share z-score helper between metrics and outliers"

# ---------------------------------------------------------------------------
# 13. io tests
# ---------------------------------------------------------------------------
cat > tests/test_io.py <<'EOF'
"""Correctness of sundial.io."""

import gzip

import pytest

from sundial.io import read_series, write_series


def test_round_trip(tmp_path):
    p = tmp_path / "events.csv"
    write_series(p, [1, 2, 3, 2])
    assert read_series(p) == [1, 2, 3, 2]


def test_header_row_skipped(tmp_path):
    p = tmp_path / "labelled.csv"
    p.write_text("value\n4\n7\nnot-a-number\n")
    assert read_series(p) == [4, 7]


def test_missing_file_raises(tmp_path):
    with pytest.raises(OSError):
        read_series(tmp_path / "nope.csv")


def test_empty_file_reads_empty(tmp_path):
    p = tmp_path / "empty.csv"
    p.write_text("")
    assert read_series(p) == []
EOF
git add -A
commit "test: io round-trips and header handling"

# ---------------------------------------------------------------------------
# 14. perf: localize hot-loop references (still linear)
# ---------------------------------------------------------------------------
cat > src/sundial/window.py <<'EOF'
"""Windowed operations over event series.

The public entry point is :func:`slide`, which computes the maximum of every
contiguous window of a fixed size in linear time using a monotonic deque of
indices.
"""

from collections import deque
from typing import List, Sequence

__all__ = ["slide"]


def slide(data: Sequence[int], size: int) -> List[int]:
    """Return the maximum of every contiguous window of ``size`` values.

    ``data`` holds non-negative integers (event magnitudes); ``size`` must be
    at least 1 (smaller values are clamped to 1).  Windows are scanned left to
    right: for a series of length *n* the result has ``n - size + 1`` entries.
    When ``size`` exceeds the series length (or the series is empty) the
    result is empty.
    """
    k = max(1, size)
    n = len(data)
    if n == 0 or k > n:
        return []
    out = [0] * (n - k + 1)
    dq: deque = deque()
    dq_append = dq.append
    dq_pop = dq.pop
    dq_popleft = dq.popleft
    data_get = data.__getitem__
    idx = 0
    for j, x in enumerate(data):
        while dq and data_get(dq[-1]) <= x:
            dq_pop()
        dq_append(j)
        if dq[0] <= j - k:
            dq_popleft()
        if j >= k - 1:
            out[idx] = data_get(dq[0])
            idx += 1
    return out
EOF
git add -A
commit "perf: localize hot-loop references in slide"

# ---------------------------------------------------------------------------
# 15. benchmark harness
# ---------------------------------------------------------------------------
mkdir -p benchmarks
cat > benchmarks/bench.py <<'EOF'
#!/usr/bin/env python3
"""Benchmark harness for sundial's hot path.

Usage:
    python3 benchmarks/bench.py [--repeats N] [SIZE ...]
    python3 benchmarks/bench.py --json OUT.json

Prints the median wall time (ms) of ``window.slide`` at each requested size
(default sizes are listed below); ``--json`` writes
``{"n": [...], "k": [...], "ms": [...]}`` instead.
"""

import argparse
import json
import random
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sundial.window import slide

DEFAULT_SIZES = [2000, 4000, 8000, 16000]


def bench_size(n: int, k: int, repeats: int) -> float:
    rng = random.Random(1009 + n)
    data = [rng.randrange(0, 1 << 20) for _ in range(n)]
    times = []
    for _ in range(repeats):
        t0 = time.perf_counter()
        slide(data, k)
        times.append(time.perf_counter() - t0)
    return statistics.median(times)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sizes", nargs="*", type=int)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--json", metavar="PATH")
    args = parser.parse_args(argv)

    sizes = args.sizes or DEFAULT_SIZES
    ks = [n // 2 for n in sizes]
    ms = [
        bench_size(n, k, args.repeats) * 1000.0 for n, k in zip(sizes, ks)
    ]
    if args.json:
        Path(args.json).write_text(
            json.dumps({"n": sizes, "k": ks, "ms": [round(m, 3) for m in ms]}, indent=2)
        )
    else:
        for n, k, m in zip(sizes, ks, ms):
            print(f"n={n:7d} k={k:7d} median_ms={m:9.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOF
cat > benchmarks/README.md <<'EOF'
# Benchmarking

`bench.py` times the sliding-window hot path at increasing input sizes.
Median of `--repeats` runs (default 5) per size, random data, fixed seed.

    python3 benchmarks/bench.py

Healthy (linear) behaviour shows `median_ms` growing roughly linearly with
`n`; a quadratic hot path shows it growing with `n^2` (roughly 4x when the
size doubles).
EOF
git add -A
commit "feat: benchmark harness in benchmarks/bench.py"

# ---------------------------------------------------------------------------
# 16. THE REGRESSION: slice maxima instead of the deque  (intentional O(n^2))
# ---------------------------------------------------------------------------
cat > src/sundial/window.py <<'EOF'
"""Windowed operations over event series.

The public entry point is :func:`slide`, which computes the maximum of every
contiguous window of a fixed size.
"""

from typing import List, Sequence

__all__ = ["slide"]


def slide(data: Sequence[int], size: int) -> List[int]:
    """Return the maximum of every contiguous window of ``size`` values.

    ``data`` holds non-negative integers (event magnitudes); ``size`` must be
    at least 1 (smaller values are clamped to 1).  Windows are scanned left to
    right: for a series of length *n* the result has ``n - size + 1`` entries.
    When ``size`` exceeds the series length (or the series is empty) the
    result is empty.
    """
    k = max(1, size)
    n = len(data)
    if n == 0 or k > n:
        return []
    out = []
    for i in range(n - k + 1):
        out.append(max(data[i : i + k]))
    return out
EOF
git add -A
commit "perf: replace deque bookkeeping with slice maxima for cache locality"

# ---------------------------------------------------------------------------
# 17. configurable spike baseline
# ---------------------------------------------------------------------------
cat > src/sundial/outliers.py <<'EOF'
"""Anomaly detection helpers built on window operations."""

from typing import List, Optional, Sequence

from .metrics import mean, stdev, zscore
from .window import slide

__all__ = ["detect_spikes"]


def detect_spikes(
    data: Sequence[int],
    size: int,
    z: float = 3.0,
    baseline: Optional[List[int]] = None,
) -> List[int]:
    """Return the right-edge indices of windows whose maximum stands out.

    Each window maximum is compared against ``mean(maxima) + z * stdev`` of
    all window maxima.  A precomputed ``baseline`` (a list of window maxima
    for the same series and size) can be supplied to skip re-computation.
    Indices are positions in ``data`` (the right edge of the offending
    window).  Series too short to open a single window produce no spike flags.
    """
    maxima = slide(data, size) if baseline is None else baseline
    if len(maxima) < 2:
        return []
    m = mean(maxima)
    s = stdev(maxima)
    if s == 0:
        return []
    cutoff = m + z * s
    return [i + max(1, size) - 1 for i, v in enumerate(maxima) if v > cutoff]
EOF
git add -A
commit "feat: let detect_spikes accept a precomputed baseline"

# ---------------------------------------------------------------------------
# 18. size-one outlier test
# ---------------------------------------------------------------------------
cat > tests/test_outliers.py <<'EOF'
"""Correctness of sundial.outliers.detect_spikes."""

import pytest

from sundial.outliers import detect_spikes
from sundial.window import slide


def test_no_spikes_in_flat_series():
    data = [10] * 40
    assert detect_spikes(data, 8, z=1.5) == []


def test_spike_windows_flagged():
    # One dominant value at index 20: exactly the windows whose maximum is
    # that value are flagged, and they line up on their right edges.
    data = [1] * 20 + [10000] + [1] * 19
    flagged = detect_spikes(data, 4, z=2.0)
    assert flagged == list(range(20, 24))


def test_short_series_no_flags():
    assert detect_spikes([5, 5, 5], 4, z=100.0) == []


def test_zero_spread_flags_nothing():
    assert detect_spikes([4, 4, 4, 4, 4, 4], 3, z=0.0) == []


def test_size_one_windows_flag_dominant_value():
    data = [1, 1, 9, 1, 1]
    maxima = slide(data, 1)
    flagged = detect_spikes(data, 1, z=1.0, baseline=maxima)
    assert flagged and data[flagged[0]] == 9


def test_precomputed_baseline_matches_recomputed():
    data = [3, 1, 4, 1, 5, 9, 2, 6]
    assert detect_spikes(data, 3, z=10.0) == detect_spikes(
        data, 3, z=10.0, baseline=slide(data, 3)
    )
EOF
git add -A
commit "test: cover spike detection with size-one windows"

# ---------------------------------------------------------------------------
# 19. describe CLI subcommand
# ---------------------------------------------------------------------------
cat > src/sundial/cli.py <<'EOF'
"""Command-line interface: inspect event series files."""

import argparse
import sys

from . import io
from .window import slide


def peek(path: str, size: int) -> None:
    series = io.read_series(path)
    for i, value in enumerate(slide(series, size)):
        print(f"{i + size - 1}\t{value}")


def describe(path: str, size: int) -> None:
    series = io.read_series(path)
    maxima = slide(series, size)
    if maxima:
        print(f"windows={len(maxima)} overall_max={max(maxima)}")
    else:
        print("windows=0")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sundial", description="Windowed analytics over event series"
    )
    sub = parser.add_subparsers(dest="command", required=True)
    p_peek = sub.add_parser("peek", help="print window maxima with window end index")
    p_peek.add_argument("path")
    p_peek.add_argument("--size", type=int, default=5)
    p_desc = sub.add_parser("describe", help="summarise window maxima")
    p_desc.add_argument("path")
    p_desc.add_argument("--size", type=int, default=5)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "peek":
        peek(args.path, args.size)
    elif args.command == "describe":
        describe(args.path, args.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOF
git add -A
commit "refactor: argparse subcommands in cli"

# ---------------------------------------------------------------------------
# 20. contributing guide
# ---------------------------------------------------------------------------
cat > CONTRIBUTING.md <<'EOF'
# Contributing

## Development loop

Run the correctness suite from the repository root:

    python3 -m pytest -q

Run the benchmark harness to check performance behaviour:

    python3 benchmarks/bench.py

Performance changes must keep `benchmarks/bench.py` scaling roughly
linearly with input size (the current hot path is the sliding-window
maximum in `src/sundial/window.py`).
EOF
git add -A
commit "docs: CONTRIBUTING and development notes"

# ---------------------------------------------------------------------------
# 21. gzip support
# ---------------------------------------------------------------------------
cat > src/sundial/io.py <<'EOF'
"""CSV persistence for event series (gzip transparently via .gz suffix)."""

import csv
import gzip
from typing import List

__all__ = ["read_series", "write_series"]


def read_series(path) -> List[int]:
    """Read a one-column CSV of integers; non-numeric rows are skipped.

    Files ending in ``.gz`` are transparently decompressed.
    """
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "rt", newline="", encoding="utf-8") as fh:
        out = []
        for row in csv.reader(fh):
            if not row:
                continue
            try:
                out.append(int(row[0].strip()))
            except ValueError:
                continue
        return out


def write_series(path, series: List[int]) -> None:
    """Write a one-column CSV with a ``value`` header row.

    Files ending in ``.gz`` are transparently compressed.
    """
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "wt", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["value"])
        for value in series:
            writer.writerow([value])
EOF
git add -A
commit "feat: read and write gzipped series automatically by extension"

# ---------------------------------------------------------------------------
# 22. gzip io tests
# ---------------------------------------------------------------------------
cat > tests/test_io.py <<'EOF'
"""Correctness of sundial.io."""

import gzip

import pytest

from sundial.io import read_series, write_series


def test_round_trip(tmp_path):
    p = tmp_path / "events.csv"
    write_series(p, [1, 2, 3, 2])
    assert read_series(p) == [1, 2, 3, 2]


def test_gzip_round_trip(tmp_path):
    p = tmp_path / "events.csv.gz"
    write_series(p, [9, 8, 7])
    with gzip.open(p, "rt", encoding="utf-8") as fh:
        text = fh.read()
    assert "9" in text
    assert read_series(p) == [9, 8, 7]


def test_header_row_skipped(tmp_path):
    p = tmp_path / "labelled.csv"
    p.write_text("value\n4\n7\nnot-a-number\n")
    assert read_series(p) == [4, 7]


def test_missing_file_raises(tmp_path):
    with pytest.raises(OSError):
        read_series(tmp_path / "nope.csv")


def test_empty_file_reads_empty(tmp_path):
    p = tmp_path / "empty.csv"
    p.write_text("")
    assert read_series(p) == []
EOF
git add -A
commit "test: gzip round-trip via io module"

# ---------------------------------------------------------------------------
# 23. version 0.2.0
# ---------------------------------------------------------------------------
cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=64", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "sundial"
version = "0.2.0"
description = "Windowed analytics over event series"
readme = "README.md"
requires-python = ">=3.9"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
EOF
cat > src/sundial/__init__.py <<'EOF'
"""sundial: windowed analytics over event series."""

from .outliers import detect_spikes
from .window import slide

__version__ = "0.2.0"
__all__ = ["slide", "detect_spikes", "__version__"]
EOF
cat > CHANGELOG.md <<'EOF'
# Changelog

## 0.2.0

- `detect_spikes` accepts a precomputed window-maxima baseline.
- `cli` gains a `describe` subcommand.
- CSV I/O transparently handles `.gz`.
- Benchmark harness added under `benchmarks/`.

## 0.1.0

- Initial release: sliding-window maximum, spike detection, CSV I/O.
EOF
git add -A
commit "chore: version 0.2.0 and changelog"

# ---------------------------------------------------------------------------
# 24. README benchmark section
# ---------------------------------------------------------------------------
cat > README.md <<'EOF'
# sundial

Windowed analytics over event series: sliding-window maxima, spike detection
and CSV persistence.

## Quickstart

```python
>>> from sundial import slide, detect_spikes
>>> slide([3, 1, 4, 1, 5, 9, 2], 3)
[4, 4, 5, 9, 9]
>>> detect_spikes([2] * 6 + [50] + [2] * 6, 3, z=3.0)
[]
```

Series are stored as one-column CSV files:

```python
>>> from sundial.io import write_series, read_series
>>> write_series("/tmp/events.csv", [1, 2, 3, 2])
>>> read_series("/tmp/events.csv")
[1, 2, 3, 2]
```

## Layout

| Path | Purpose |
|---|---|
| `src/sundial/` | the library |
| `tests/` | correctness suite (`python3 -m pytest -q`) |
| `benchmarks/` | performance harness |
| `examples/` | sample programs |

## Benchmark

The hot path (sliding-window maximum) ships with a harness:

```console
$ python3 benchmarks/bench.py
n=   2000 k=   1000 median_ms=    0.42
n=   4000 k=   2000 median_ms=    1.66
n=   8000 k=   4000 median_ms=    1.62
n=  16000 k=   8000 median_ms=    4.06
```

`median_ms` should grow roughly linearly with `n`. If it grows
quadratically, a performance regression has been introduced somewhere in the
history — bisect it.

The same numbers can be written to a JSON report with
`python3 benchmarks/bench.py --json bench.json`.
EOF
git add -A
commit "docs: benchmark quickstart in README"

# ---------------------------------------------------------------------------
# 25. example script
# ---------------------------------------------------------------------------
mkdir -p examples
cat > examples/maxwatch.py <<'EOF'
#!/usr/bin/env python3
"""Print the current window maximum for a growing event series.

Usage:
    python3 examples/maxwatch.py <series.csv> <window>
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sundial.io import read_series
from sundial.window import slide


def main(argv) -> int:
    if len(argv) != 3:
        print("usage: maxwatch.py <series.csv> <window>", file=sys.stderr)
        return 2
    size = int(argv[2])
    series = read_series(argv[1])
    for value in slide(series, size):
        print(value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
EOF
git add -A
commit "feat: example script for monitoring window maxima"

# ---------------------------------------------------------------------------
# Final housekeeping: clean tree, refuse nothing; print the log.
# ---------------------------------------------------------------------------
git status --porcelain | head
echo "TOTAL_COMMITS=$(git rev-list --count HEAD)"
git log --format='%h %s' | head -30