# Character-range containment is wrong at the domain bounds

## Situation

`/app/src` is a shallow, pinned clone of the Apache Commons Lang library
(`https://github.com/apache/commons-lang`), checked out at upstream commit
`596269f16d33cd4a20223978c245a15c898c5084`. The clone is detached at that
commit and contains no other history. Java 21 (OpenJDK with `javac`) and
Maven 3.9.9 (`/opt/apache-maven-3.9.9/bin/mvn`) are installed, and a Maven
local repository pre-populated with everything this project's build needs is
at `/opt/m2repo`. There is **no network** at trial time: `pip`, `curl` and
`git fetch` will not work; everything you need is already in the image.

The module contains a package-private **contiguous character-range utility**
in package `org.apache.commons.lang3`: a range is a start character, an end
character and an optional negation flag, and a negated range is a compact way
to say *every character except those in [start, end]*. It exposes two
containment operations: *does this set contain character `c`?* and *does this
set fully contain the whole set denoted by another range?* Your work involves
the second one (`contains` of one range in another).

## The bug

The second containment query answers correctly for ordinary ranges, and it
also handles the case where the *receiver* is a negated range. But when the
**argument** is a negated range, the behaviour is wrong at the edges of the
character domain, which is `0 .. Character.MAX_VALUE`:

- A negated argument denotes *the whole domain minus a block*. When that
  excluded block **touches the start of the domain** (its lower bound is the
  first character), the remaining set collapses to a single contiguous
  interval: *everything from the block's end + 1 on*. When the block
  **touches the end of the domain** (its upper bound is
  `Character.MAX_VALUE`), it collapses to *everything up to the block's
  start - 1*. Excluding the **entire** domain leaves the empty set.
- For those collapsed cases the query answers `false` where the answer
  should be `true`. Only when the outer range is the full domain does it
  give the right answer; every proper range fails even when it plainly
  contains the collapsed complement.

Concrete symptom:

- `is('x').contains(isNotIn(0, Character.MAX_VALUE))` should return `true`
  (the argument denotes the empty set) but returns `false`.
- `isIn('a', Character.MAX_VALUE).contains(isNotIn(0, 'a' - 1))` should
  return `true` (the argument denotes `['a', Character.MAX_VALUE]`, which the
  receiver spans exactly) but returns `false`.
- `isIn(0, 'a').contains(isNotIn('b', Character.MAX_VALUE))` should return
  `true` (the argument denotes `[0, 'a']`) but returns `false`.

An exclusion whose block is fully interior (touches neither domain boundary)
keeps two intervals and is still containable only by the full domain — that
case must keep working exactly as it does today.

## Reproducing the failure

The image ships a self-contained reproduction:

```
/app/probe.sh
```

It compiles the range utility together with a small check program and runs
it. While the bug is present it prints the failing containment checks,
`RESULT=false`, and exits with status 1; after a correct fix it prints
`RESULT=true` and exits with status 0.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that the containment
query returns the mathematically correct answer for **every** negated
argument that touches a domain boundary — including the empty-set case and
both single-interval cases — and so that every other containment behaviour is
unchanged (containment among ordinary ranges, negated receivers, and
interior excluded blocks).

Drive your work with the project's own build and test runner from `/app/src`.
All of the project's tests are green at the pinned commit and it is safe to
run any subset, for example:

```
cd /app/src && /opt/apache-maven-3.9.9/bin/mvn -B -q test \
  -Dtest='CharRangeTest,CharSetTest,RangeTest,IntegerRangeTest,LongRangeTest,DoubleRangeTest' \
  -DfailIfNoTests=false -Dspotless.check.skip=true -Dcheckstyle.skip=true \
  -Drat.skip=true -Denforcer.skip=true -Dmaven.repo.local=/opt/m2repo
```

If you add test files of your own while you work, remove them before you
finish: the working tree you leave behind is what gets judged, and the
verifier's provenance rules below apply to it.

## Constraints

- Network is unavailable; everything needed is installed already
  (`-Dmaven.repo.local=/opt/m2repo` makes Maven use the warm repository).
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch from the network, or change
  build files. Files under `/opt/golden`, `/tests` and `/solution` are
  harness-owned; do not touch them.
- The verifier asserts that the working tree is still at the pinned commit,
  that exactly one commit exists, that no history was fetched, that no
  tracked file was deleted, and that the only modified tracked source file
  is the implementation file of the range utility (the single file the fix
  requires; your change must live there and nowhere else).

## What the verifier checks

1. The tree is still at commit `596269f16d33cd4a20223978c245a15c898c5084`
   with no other history, no tracked deletions, at least one modification in
   the range utility's implementation file, and no tracked modification
   anywhere else.
2. The direct reproduction `/app/probe.sh` exits 0.
3. The project's own upstream regression test for this behaviour passes (it
   is kept out of the tree at `/opt/golden/` and copied in by the verifier).
4. The project's own existing tests around this utility still pass.
5. Hidden cases over boundary-adjacent negated ranges that the regression
   test does not use pass, plus guards that interior exclusions and negated
   receivers are unchanged.

Deliverable: the repaired `/app/src` tree.