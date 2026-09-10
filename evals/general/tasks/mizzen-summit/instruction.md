# mizzen-summit

You are working in a real upstream codebase: Apache Kafka 4.3.1, checked out at
`/app/src` (a single, shallow commit; the working tree starts clean). Your job is
to implement one precisely-specified capability in it, scoped to a single
module, and to prove your implementation with the project's own test tooling.
You are NOT told where the change goes: finding the right place in a 7,232-file
tree is part of the task.

## Environment

- JDK 21 and git are installed. `gradlew` (Gradle 9.2.1 wrapper) is in `/app/src`.
- There is **no network** in this container. Everything you need is already
  baked in: the Gradle distribution, all third-party dependencies, and the
  compiled outputs of the modules you will need. Gradle runs offline; always
  pass `--offline` (the flag also keeps builds from attempting network access).
- The Gradle user home is `/app/.gradle-home`. Do not move or delete it.
- `cpus = 1`: the container has one vCPU. Never run builds in parallel (the
  Gradle settings already limit workers to 1).
- Builds were warm-started at image build time, so a no-op
  `./gradlew :<module>:test --offline` takes about half a minute. After you
  edit a Java file, the same command recompiles incrementally (tens of seconds)
  and reruns the selected tests.

## What the codebase is

Kafka ships multiple "coordinator" runtimes (group, share, and transaction
coordination). All of them serialize asynchronous work through one shared
concurrency primitive: a thread-safe accumulator class that batches incoming
events, grouping them by a per-event key. Its contract:

- Events are appended to the tail (or head) of a per-key queue.
- `poll()` returns one event at a time; while an event with a given key is in
  flight, no further event with that key is handed out, so per-key processing
  stays single-threaded.
- `done(event)` releases that key so the next queued event for it can be
  polled.
- `size()` reports how many events are currently queued.
- `close()` shuts the accumulator down; adding after close throws
  `RejectedExecutionException` immediately.

Both `addLast` and `addFirst` can throw `RejectedExecutionException` when the
accumulator is closed.

## Required change: an optional bounded capacity

Operators need a way to bound how many events this accumulator can hold, so a
stalled consumer cannot make the runtime hold an unbounded amount of work. Add
support for an optional maximum capacity, with exactly these semantics:

1. A way to construct the accumulator with a maximum capacity `N` (an `int`).
2. When the accumulator already holds `N` events, any attempt to add another
   event — via either add path — must throw `java.util.concurrent.
   RejectedExecutionException` immediately, leaving the accumulator completely
   unchanged: same contents, same `size()`, same keys available.
3. Capacity counts every queued event regardless of key or add path. Removing
   an event with `poll()` frees capacity immediately: an add that was rejected
   becomes accepted as soon as the number of queued events drops below `N`,
   without requiring a `done()` call.
4. `done()` does not by itself change the count of queued events, so it does
   not by itself free capacity.
5. A non-positive capacity (0 or negative) must be rejected at construction
   with `IllegalArgumentException`.
6. The existing no-argument constructor must keep working with no capacity
   limit — every existing call site and all existing behavior must be
   unchanged.

The implementation must be thread-safe under the same lock discipline the class
already uses. Do not change any public API signatures other than adding the new
constructor(s) the change needs.

## What belongs where

The change lives entirely in the module that owns this primitive; you may
modify source files only inside **that one module's** `src` directory tree.
Do not modify any other module, any `build.gradle`, `settings.gradle`, or other
build plumbing, any test file, or anything under `tests/`. Do not add new files
outside the module's `src` tree. The instruction describes the change's
behaviour; the module and class are for you to find.

## Deliverables

1. `/app/src` — the tree with your change applied, compiling, with the
   accumulator's existing unit-test class still green (see below).
2. `/app/summary.md` — a short (at least 5, at most 40 lines) note in your own
   words containing: the fully-qualified name of the class you modified, the
   module it lives in, the semantics you chose for capacity enforcement, and
   the exact command(s) you ran to verify.

## Verifying your work (recommended path)

The module's own unit tests use the project's JUnit setup. To run one test
class of one module:

```
cd /app/src && ./gradlew :<module>:test --tests '<fully.qualified.ClassName>' --offline
```

(The `<module>` is the Gradle project name for the module — find it, run the
accumulator's existing test class, and confirm it passes before and after your
change.) Recommended loop:

1. Run the existing unit-test class of the accumulator before changing anything
   (should pass; about a minute).
2. Implement the bounded-capacity change.
3. Re-run that same test class — nothing existing may break. Add a couple of
   quick checks of the new behaviour if you want (a scratch test file may help,
   but the graders run their own cases against the class regardless).
4. Write `/app/summary.md`.

Do NOT run the whole Kafka test suite or `./gradlew test` (too slow at
1 vCPU), and do not `jar`/`package`/`publish` anything.

## Grading

The verifier (the container's own /tests) will, on a clean `/app/src`:

- confirm that the only source changes in the tree are inside the module's
  `src` directory, and that `/app/summary.md` exists;
- place its own hidden JUnit test classes into the module's test tree — two
  classes probing the capacity semantics from different angles (exact-capacity
  rejection, state preservation on rejection, capacity freed by `poll`, the
  per-key reclaim interaction, constructor input validation, and the unbounded
  default) — and run them together with the accumulator's existing test class
  in ONE `./gradlew :<module>:test --tests ... --offline` invocation.

Reward is binary: 1 if every one of those tests passes, `/app/summary.md`
exists, and no source outside the module changed; otherwise 0.