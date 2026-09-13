#!/usr/bin/env python3
"""Apply the minimal fix for scikit-image issue #7648 to EllipseModel.estimate.

Insert the len(data) < 5 guard at the top of estimate(), matching the upstream
fix (commit 96834cf3): a fit requested with fewer than five data points emits a
RuntimeWarning explaining that at least five points are needed and returns
False before any fitting math runs.

Idempotent: if the guard is already present the file is left untouched.
"""

import sys

GUARD = """        if len(data) < 5:
            warn(
                "Need at least 5 data points to estimate an ellipse.",
                category=RuntimeWarning,
                stacklevel=2,
            )
            return False

"""

# Unique anchor: this comment block appears only inside EllipseModel.estimate.
MARKER = """        # Original Implementation: Ben Hammel, Nick Sullivan-Molina
        # another REFERENCE: [2] http://mathworld.wolfram.com/Ellipse.html
        _check_data_dim(data, dim=2)

"""


def main(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if "Need at least 5 data points to estimate an ellipse." in src:
        print(f"{path}: guard already present, no-op")
        return
    found = src.count(MARKER)
    assert found == 1, f"expected exactly one insertion point, found {found}"
    src = src.replace(MARKER, MARKER + GUARD)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"{path}: applied the fewer-than-five-points guard")


if __name__ == "__main__":
    main(sys.argv[1])