#!/usr/bin/env python3
"""Apply the minimal upstream fix for the ballast-deepwater bug.

Two unchecked signed negations overflow for extreme interval fields:

1. SubtractTimeOperator::Operation (TIME and TIMETZ overloads) in
   src/function/scalar/operator/subtract.cpp does `right.micros =
   -right.micros;` even when right.micros == INT64_MIN, so subtracting an
   interval whose microseconds component is the 64-bit signed minimum from
   a TIME/TIMETZ value wraps and returns a silently wrong time.

2. Interval::Invert in src/common/types/interval.cpp negates all three
   interval fields (days, micros, months) with no bounds check; it is on the
   DATE/TIMESTAMP minus interval path, so the same extreme values wrap there
   too.

The fix guards every negation: throw OutOfRangeException before negating any
field that equals its numeric minimum. These are byte-for-byte the checks
the upstream fix added.

Usage: fix_interval_negation.py /app/src
"""
import sys
from pathlib import Path

SUBTRACT = Path("src/function/scalar/operator/subtract.cpp")
INTERVAL = Path("src/common/types/interval.cpp")

GUARD_MICROS = (
    "\tif (right.micros == NumericLimits<int64_t>::Minimum()) {\n"
    '\t\tthrow OutOfRangeException("Interval micros value out of range");\n'
    "\t}\n"
)

GUARDS_INVERT = (
    "\tif (interval.days == NumericLimits<int32_t>::Minimum()) {\n"
    '\t\tthrow OutOfRangeException("Interval days value out of range");\n'
    "\t}\n"
    "\tif (interval.micros == NumericLimits<int64_t>::Minimum()) {\n"
    '\t\tthrow OutOfRangeException("Interval micros value out of range");\n'
    "\t}\n"
    "\tif (interval.months == NumericLimits<int32_t>::Minimum()) {\n"
    '\t\tthrow OutOfRangeException("Interval months value out of range");\n'
    "\t}\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_interval_negation.py <path-to-duckdb-src>")
        return 2
    src = Path(sys.argv[1])
    if not (src / SUBTRACT).is_file():
        print(f"ERROR: {SUBTRACT} not found under {src}", file=sys.stderr)
        return 1

    # --- subtract.cpp: TIME and TIMETZ overloads -----------------------------
    text = (src / SUBTRACT).read_text(encoding="utf-8")
    buggy_time = (
        "template <>\ndtime_t SubtractTimeOperator::Operation(dtime_t left, interval_t right) {\n"
        "\tright.micros = -right.micros;\n"
    )
    fixed_time = (
        "template <>\ndtime_t SubtractTimeOperator::Operation(dtime_t left, interval_t right) {\n"
        + GUARD_MICROS
        + "\tright.micros = -right.micros;\n"
    )
    buggy_timetz = (
        "template <>\ndtime_tz_t SubtractTimeOperator::Operation(dtime_tz_t left, interval_t right) {\n"
        "\tright.micros = -right.micros;\n"
    )
    fixed_timetz = (
        "template <>\ndtime_tz_t SubtractTimeOperator::Operation(dtime_tz_t left, interval_t right) {\n"
        + GUARD_MICROS
        + "\tright.micros = -right.micros;\n"
    )
    fixed = text.replace(buggy_time, fixed_time).replace(buggy_timetz, fixed_timetz)
    if fixed == text or fixed.count("Interval micros value out of range") != 2:
        print("ERROR: expected buggy TIME/TIMETZ negation blocks not found in "
              f"{SUBTRACT}; refusing to patch", file=sys.stderr)
        return 1
    (src / SUBTRACT).write_text(fixed, encoding="utf-8")
    print(f"patched {SUBTRACT}: TIME/TIMETZ micros negation now bounds-checked")

    # --- interval.cpp: include + Invert guards --------------------------------
    text = (src / INTERVAL).read_text(encoding="utf-8")
    fixed = text.replace(
        '#include "duckdb/common/string_util.hpp"\n',
        '#include "duckdb/common/string_util.hpp"\n#include "duckdb/common/limits.hpp"\n',
    )
    buggy_invert = (
        "interval_t Interval::Invert(interval_t interval) {\n"
        "\tinterval.days = -interval.days;\n"
        "\tinterval.micros = -interval.micros;\n"
        "\tinterval.months = -interval.months;\n"
        "\treturn interval;\n"
        "}\n"
    )
    fixed_invert = (
        "interval_t Interval::Invert(interval_t interval) {\n"
        + GUARDS_INVERT
        + "\tinterval.days = -interval.days;\n"
        "\tinterval.micros = -interval.micros;\n"
        "\tinterval.months = -interval.months;\n"
        "\treturn interval;\n"
        "}\n"
    )
    fixed = fixed.replace(buggy_invert, fixed_invert)
    checks = [
        "#include \"duckdb/common/limits.hpp\"\n",
        "Interval days value out of range",
        "Interval micros value out of range",
        "Interval months value out of range",
    ]
    if not all(c in fixed for c in checks):
        print("ERROR: expected buggy Interval::Invert block not found in "
              f"{INTERVAL}; refusing to patch", file=sys.stderr)
        return 1
    (src / INTERVAL).write_text(fixed, encoding="utf-8")
    print(f"patched {INTERVAL}: Interval::Invert now bounds-checks days/micros/months")
    return 0


if __name__ == "__main__":
    sys.exit(main())