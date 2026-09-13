# Interval subtraction can silently return a wrong time

## Situation

`/app/src` is a shallow, pinned clone of the DuckDB source repository
(`https://github.com/duckdb/duckdb`) at upstream commit
`8616efa9da9921b9111fe46373af7936a5d96d16`, checked out in detached HEAD.
The release engine has already been configured and compiled, so everything
works entirely offline. There is **no network** at trial time: `git fetch`,
`curl` and any other network use will fail.

The prebuilt CLI binary is `/app/src/build/release/duckdb` and the project's
own test runner is `/app/src/build/release/test/unittest`. Because the build
is already done, a source edit only triggers an incremental recompile plus a
relink:

```
cd /app/src && ninja -C build/release
```

Each cycle is on the order of minutes, not hours. Do **not** reconfigure or
clean the build directory.

## The bug

Subtracting an interval whose microseconds component is extremely negative
from a `TIME` (or `TIMETZ`) value does not fail. Run this against the prebuilt
CLI:

```
/app/src/build/release/duckdb -c "SELECT TIME '12:00:00' - INTERVAL '-4611686018427387904 microseconds -4611686018427387904 microseconds';"
```

Instead of an error, the result is a completely wrong time (`07:59:05.224192`
for `12:00:00`) — silently incorrect arithmetic with no diagnostic. The
interval literal above is perfectly valid: its two components add up to
exactly `-9223372036854775808` microseconds, the minimum value a 64-bit
signed integer can hold (`-9223372036854775808`), so the subtraction asks
for the negation of that extreme value, which cannot be represented.

The same failure can be provoked through `DATE`/`TIMESTAMP` operands, whose
subtraction internally applies the same "negate the interval, then add"
logic, and through the interval's other components (a day/month field at
its own signed minimum). In every such case a clearly worded
`Out of Range Error` must be raised instead of a wrong value.

This is what is expected after a correct fix — `TIME` and `TIMETZ`:

```
D SELECT TIME '12:00:00' - INTERVAL '-4611686018427387904 microseconds -4611686018427387904 microseconds';
Out of Range Error: Interval micros value out of range
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. The project's own regression test for this bug,
   `test/sql/types/test_interval_negation_overflow.test` (already present in
   the tree), passes. Run it with the project's test runner:

   ```
   cd /app/src && build/release/test/unittest "test/sql/types/test_interval_negation_overflow.test"
   ```

   At the pinned commit it fails (the two extreme-value statements each
   return a wrong time instead of an error, and the runner reports
   `test cases: 1 | 1 failed`); after your fix it must print
   `All tests passed`. The test also checks that ordinary interval
   subtraction keeps working, so those cases enforce that your fix does not
   over-reach.

2. Subtracting a `TIME` or `TIMETZ` value by an interval whose microseconds
   component is the 64-bit signed minimum raises
   `Out of Range Error: Interval micros value out of range`, never a wrong
   time; the same holds for `DATE`/`TIMESTAMP` operands, and for day/month
   fields at their signed minimum the equivalent `Interval days value out of
   range` / `Interval months value out of range` error is raised.

3. All normal interval arithmetic still produces exactly the right values:
   no case that worked before may change its result, and no error may be
   raised where the arithmetic is representable.

Run the project's own interval and time-of-day suites to confirm you broke
nothing else, e.g.:

```
cd /app/src && build/release/test/unittest "test/sql/types/interval/*" && build/release/test/unittest "test/sql/types/time/test_time.test" && build/release/test/unittest "test/sql/types/time/test_time_tz.test" && build/release/test/unittest "test/sql/types/time/time_limits.test"
```

The tests in the tree are the spec: take them as authoritative.

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or
  change build files, and do not add or rename files inside the repository.
- The regression-test file `test/sql/types/test_interval_negation_overflow.test`
  is part of the image the way the fix intends it; the verifier checks that
  it stays byte-identical.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the only differences from it are
   the minimal source change that fixes the bug plus the regression-test file
   the image already carries, and nothing new inside the repository.
2. The regression test above passes through the project's own test runner,
   and the project's own interval and time-of-day suites stay green.
3. Hidden cases: further `TIME`/`TIMETZ`/`DATE`/`TIMESTAMP` subtractions that
   hit the same code path from inputs the upstream regression test does not
   use (other times, a non-UTC timezone offset, day-field extremes) must
   raise the exact out-of-range errors above, and an ordinary subtraction
   must still return the exact correct value.

Deliverable: the repaired `/app/src` tree.