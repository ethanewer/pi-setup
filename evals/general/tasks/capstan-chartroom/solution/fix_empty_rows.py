#!/usr/bin/env python3
"""Fix statsmodels' describe()/Description on zero-row (empty) input.

descriptivestats.Description.numeric computed the mode with
`df.apply(_mode).T`: on a zero-row frame pandas' empty-result path returns a
2-element result for a 1-element index and raises "ValueError: Length of
values (2) does not match length of index (1)". It also applied
_safe_jarque_bera per column and indexed the transposed result at jb[2]/jb[3]
for skew/kurtosis; on a frame with no columns left (all-categorical input)
the apply returns an empty frame with no columns and those lookups raise
"KeyError: 2".

Both quantities are undefined when there are no observations. Short-circuit
them to NaN: build a NaN mode and mode-count vector of length k when the
frame has zero rows, and build a k x 4 all-NaN Jarque-Bera frame (columns
0..3) when there are no rows or no numeric columns, so the skew/kurtosis/JB
lookups below resolve to NaN instead of raising, and the table comes out with
nobs == missing == 0 and NaN statistics for every column, matching the
summary the underlying data library produces for the same empty input.

Usage: fix_empty_rows.py [path-to-descriptivestats.py]
"""
import pathlib
import sys

DEFAULT = "/app/src/statsmodels/stats/descriptivestats.py"

OLD_MODE = """        mode_values = df.apply(_mode).T
        if mode_values.size > 0:
            if isinstance(mode_values, pd.DataFrame):
                # pandas 1.0 or later
                mode = np.asarray(mode_values[0], dtype=float)
                mode_counts = np.asarray(mode_values[1], dtype=np.int64)
            else:
                # pandas before 1.0 returns a Series of 2-elem list
                mode = []
                mode_counts = []
                for idx in mode_values.index:
                    val = mode_values.loc[idx]
                    mode.append(val[0])
                    mode_counts.append(val[1])
                mode = np.atleast_1d(mode)
                mode_counts = np.atleast_1d(mode_counts)
        else:
            mode = mode_counts = np.empty(0)
"""
NEW_MODE = """        if df.shape[0] == 0:
            # No observations: the mode is undefined. Skip the apply since
            # pandas' empty-result path mis-sizes the output, raising
            # "Length of values (2) does not match length of index" (GH#9891).
            mode = np.full(k, np.nan)
            mode_counts = np.full(k, np.nan)
        else:
            mode_values = df.apply(_mode).T
            if mode_values.size > 0:
                if isinstance(mode_values, pd.DataFrame):
                    # pandas 1.0 or later
                    mode = np.asarray(mode_values[0], dtype=float)
                    mode_counts = np.asarray(mode_values[1], dtype=np.int64)
                else:
                    # pandas before 1.0 returns a Series of 2-elem list
                    mode = []
                    mode_counts = []
                    for idx in mode_values.index:
                        val = mode_values.loc[idx]
                        mode.append(val[0])
                        mode_counts.append(val[1])
                    mode = np.atleast_1d(mode)
                    mode_counts = np.atleast_1d(mode_counts)
            else:
                mode = mode_counts = np.empty(0)
"""

OLD_JB = """        jb = df.apply(
            lambda x: list(_safe_jarque_bera(x.dropna())), result_type="expand"
        ).T
"""
NEW_JB = """        if df.shape[0] > 0 and df.shape[1] > 0:
            jb = df.apply(
                lambda x: list(_safe_jarque_bera(x.dropna())),
                result_type="expand",
            ).T
        else:
            # No observations (or no numeric columns): Jarque-Bera is
            # undefined. Build a NaN frame with the expected four columns so
            # the skew/kurtosis/JB lookups below do not raise KeyError
            # (GH#9891).
            jb = pd.DataFrame(np.nan, index=cols, columns=range(4))
"""


def main() -> int:
    target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    text = target.read_text()
    if NEW_MODE in text and NEW_JB in text:
        print(f"ok: {target} already carries the zero-row guards")
        return 0
    if OLD_MODE not in text or OLD_JB not in text:
        print(f"error: could not locate the insertion points in {target}",
              file=sys.stderr)
        return 1
    target.write_text(text.replace(OLD_MODE, NEW_MODE, 1).replace(OLD_JB, NEW_JB, 1))
    print(f"ok: applied the zero-row guards to {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())