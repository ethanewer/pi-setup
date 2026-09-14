# String padding can crash the whole process instead of doing nothing

## Situation

`/app/src` is a shallow, pinned clone of the Apache Commons Lang repository
(`https://github.com/apache/commons-lang`) at upstream commit
`170e9f28ad2667a9b0c80480c2a5a13cb4a53257`, checked out in detached HEAD.
JDK 21 and Maven 3.9.9 (on `PATH` as `mvn`) are installed, and the module
plus its test suite were compiled once at image build time, with all Maven
dependencies cached. Everything works **fully offline** — there is no network
at trial time, and `git fetch`, `curl`, `wget` and any other network use
fail.

Repair cycle — compiles only what changed, then runs one test class:

```
cd /app/src
mvn -B test -Dtest='StringUtilsTest' -DfailIfNoTests=false \
  -Dspotless.check.skip=true -Dcheckstyle.skip=true \
  -Drat.skip=true -Denforcer.skip=true
```

The image also contains a snapshot of the compiled classes exactly as they
are in this (buggy) checkout, at `/opt/prefix-classes` — a reference of the
pre-fix behaviour you can compile and run Java programs against
(`javac -cp /opt/prefix-classes -d /tmp X.java`).

## The bug, as a user would report it

Padding is a library feature that pads a string out to a requested length —
on the left (`leftPad`) or on the right (`rightPad`) — filling the gap with
either a single character or a repeated substring. The documented contract
for every padding method includes the obvious case: **when the requested size
is not greater than the string's own length, the string is returned
unchanged** — no padding, no allocation.

In this checkout that contract is broken for a whole family of requested
sizes. Instead of returning the input unchanged, the call makes the JVM run
out of heap trying to materialize a gigantic character array, and dies with
`java.lang.OutOfMemoryError: Java heap space` — an unchecked error that
application code cannot catch. A server that pads values derived from
untrusted lengths (session tokens, user-interpreted widths, binary
length-prefix decoding) crashes outright, taking the whole process down.

Symptoms you will see while probing:

- the crash is an uncaught `java.lang.OutOfMemoryError` whose stack points at
  the padding code, not at your call;
- with a capped heap (`java -Xmx256m ...`) it fails fast and deterministically;
- some extreme sizes are fine and crash-free, others are not — the crash only
  happens for sizes inside a specific band at one end of the `int` range, and
  the band depends on the length of the string being padded;
- once you find one crashing size, every method that pads has the same
  problem whenever its requested size falls in that band.

The required behaviour is precise: for **any** requested `int` size that is
not greater than the string length, every padding method must return the
original string unchanged (a no-op, exactly as the contract says); padding to
a size larger than the string length must keep working exactly as it does
today.

## What you need to do

1. **Write your own failing reproduction first, before changing anything.**
   Create `/app/repro/PadRepro.java`, a single Java source file with a
   `main` method that demonstrates the bug in this checkout using only the
   public padding API. Contract:
   - it must crash or fail (exit non-zero) when run against the classes in
     this checkout as-is: at least one extreme-size call must trigger the
     heap-exhaustion failure; `java -Xmx256m` keeps the failure fast and
     deterministic (1 - 2 seconds);
   - it must check the real return values, not just call the API: every
     padding call's result is compared against the documented contract
     (unchanged string for sizes not greater than the length, correct padded
     string for larger sizes), and it exits `0` only if **all** checks pass
     and exits non-zero otherwise;
   - it must not catch `Throwable`/`Error`/`OutOfMemoryError`; the
     reproduction shows the raw behaviour;
   - it uses only the public API of the library — nothing project-internal,
     nothing from `src/main` sources.
   Compile and run it against the checkout's compiled classes
   (`javac -cp /app/src/target/classes -d /tmp /app/repro/PadRepro.java &&
   java -Xmx256m -cp /app/src/target/classes:/tmp PadRepro`). In this
   checkout it must fail. Keep this file as a deliverable: the verifier
   recompiles and reruns exactly this file, and requires it to fail against
   the pre-fix class snapshot and to pass after your fix.

2. **Fix the bug** so the contract above holds and the project's own test
   suite passes:
   - `StringUtilsTest` must report `Tests run: 173, Failures: 0, Errors: 0`
     (the regression checks for these sizes, plus all pre-existing padding
     behaviour — exact-length pads, bigger-than-length pads, negative
     non-crashing sizes, unicode padding, `null` and empty pad strings —
     must still pass);
   - your reproduction now passes too (`exit 0`).

## Constraints

- Network is unavailable; everything needed is installed and cached.
- The clone at `/app/src` is a deliverable. Change in place only what the fix
  requires — a minimal change to **one library source file**. Do not modify,
  add or delete test files, build configuration, or any other file in the
  repository (the verifier requires the working tree to differ from the
  pinned commit in that single library source file, and nothing else); do not
  rewrite history, add remotes, fetch, stash or commit; keep HEAD where it is.
- `/app/repro/PadRepro.java` is the other deliverable. Keep it unchanged once
  it is written — the verifier must run the same file you used to prove the
  bug.
- `/opt/golden`, `/tests` and `/solution` are owned by the harness verifier;
  do not read, write or modify them.

## What the verifier checks

1. Tree provenance: still the pinned commit; the fix commit is not reachable
   in the clone; the only difference from the pinned tree is the one library
   source file your fix changes.
2. Your reproduction `/app/repro/PadRepro.java`: fails against the pre-fix
   class snapshot (it genuinely demonstrates the bug) and passes against the
   repaired build.
3. The project's own suite: the tree is rebuilt from your sources and
   `StringUtilsTest` must report `Tests run: 173, Failures: 0, Errors: 0`,
   including the upstream regression methods for extreme requested sizes.
4. Hidden cases exercising the same code path from inputs the upstream tests
   do not use: an overflow-band sweep across many string lengths and both
   pad kinds, and exact boundary sizes with unicode, embedded-NUL, null and
   empty-pad-string inputs — each must pass the repaired build and fail the
   pre-fix build.

Deliverables: the repaired `/app/src` tree and `/app/repro/PadRepro.java`.