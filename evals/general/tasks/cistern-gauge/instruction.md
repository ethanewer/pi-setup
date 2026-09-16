# cistern-gauge: median baseline assessment

You are handed a working Java repository: the **cistern-gauge reactor**, a
multi-module Maven project that turns reservoir level telemetry into
assessments and reports. The whole suite passes today. One requested behaviour
change is not yet implemented. Implement it, keep every other behaviour intact,
and leave the repository in a state where **the full reactor build runs green,
including with additional tests the verifier will drop in**.

## Environment

- Work inside `/app` — the reactor root (reactor `pom.xml` is at
  `/app/pom.xml`, and `/app/README.md` explains the layout).
- Java 21 (`javac`/`java`), Maven 3.8.7 and git are installed. The local Maven
  cache is pre-warmed with every dependency the reactor needs, so build offline:
  `mvn -o -q -B -f /app/pom.xml clean verify` (the `-o` flag is required:
  there is **no network** in this container, and the build must not try to
  reach Maven Central).
- The repository ships as a git repository with full history. Keep the history
  (do not delete `.git`, do not reset it away); you may commit your changes or
  leave them in the working tree, either is fine.
- One CPU, 4 GB of RAM.

## The repository

Four Maven modules, each with its own `pom.xml`, main sources under
`src/main/java` and a JUnit 5 test suite under `src/test/java`:

| module | role |
|---|---|
| `cistern-model` | units, samples, windows, thresholds, severities, codecs |
| `cistern-core`  | level strategies behind the `LevelAssessor` contract, the named strategy registry, the assessment engine |
| `cistern-report`| structured reports and deterministic text/JSON renderers; depends on `cistern-core` only through the `LevelAssessor` interface |
| `cistern-cli`   | `assess`, `report`, `inspect`, `convert`, `history`, `compare`, `version` commands |

Read `docs/ARCHITECTURE.md` before touching anything: it describes the
strategy boundary the other modules rely on.

## The requested change (new behaviour)

The **baseline** level assessment is currently estimated from the
**arithmetic mean** of the window's sample values. From now on it must be
estimated from the **median**:

- Sort the window's values and take the middle value. For an **even-sized**
  window, take the arithmetic mean of the two middle values of the sorted
  window.
- The level is that median divided by the reservoir capacity, saturated into
  `[0, 1]` exactly as today.
- Every user-visible string in the repository that describes the baseline
  assessment **as a mean** must be updated so it describes the median instead
  (this includes the strategy's own description as surfaced in reports, CLI
  output and stored JSON — the *model-level* `mean` statistic of a window is
  a different, unrelated thing and must stay the arithmetic mean).
- Any shipped test that asserted the old mean-based numbers is yours to
  update so the suite reflects the new behaviour.

The other four strategy families (and the default-selection rules) must behave
**exactly** as before. The `window.mean` statistic, the report format and key
order, and the public API of all four modules — every public class, method and
field — must remain unchanged.

Examples of the required semantics:

- window `{1, 2, 3, 4}` → median `2.5` → level `0.0025` at capacity 1000
- window `{9, 2, 5, 1, 7}` → median `5` → level `0.005`
- window `{3000, 4000, 5000}` → median `4000` → level `1.0` (saturated)
- empty window → level `0.0`

## Acceptance criteria

The verifier will:

1. Drop hidden JUnit 5 test files into `cistern-core/src/test/java` and
   `cistern-report/src/test/java` (they exercise the median semantics above
   plus the report module's continued operation through the interface), then
   run `mvn -o -q -B -f /app/pom.xml clean verify` on the whole reactor —
   every module's tests, shipped and hidden, must pass;
2. Check that **no module's public API was deleted** (public classes, methods
   and fields are compared against the pristine reactor's surface);
3. Check that the repository still holds its git history and at least
   4000 lines of Java across the four modules.

## Deliverables

- `/app/pom.xml` — the reactor build file, unchanged in role (still builds all
  four modules).
- `/app/` — the reactor working tree containing the implemented change.

Do not modify anything outside `/app`. When you believe the change is complete,
verify it yourself with

```bash
cd /app && mvn -o -q -B -f /app/pom.xml clean verify
```

before finishing; a red build is a failing task.