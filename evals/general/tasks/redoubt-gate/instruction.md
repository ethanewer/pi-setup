# redoubt-gate: repair a Maven project with a poisoned dependency graph

Somebody handed you `/app/service`, a Java 21 + Maven project for an
application called the redoubt-gate. It compiles cleanly, but its JUnit test
suite dies at runtime:

```
NoSuchMethodError: 'java.lang.String com.example.formatter.Formatter.format(java.lang.String, char)'
```

The application sources are not the problem — read them and they are plainly
correct. The disease is in the **dependency graph**: two versions of one
library can be reached from this project through different paths, and Maven
resolves the wrong one, so the bytecode that runs is not the bytecode the
tests were written against. Your job is to repair `/app/service` so that the
**correct** version of that library wins the graph, and to keep it fixed
permanently.

## Environment

- JDK 21 (`java`, `javac`) and Maven 3.8.7 are installed. **There is no
  network** in this container.
- `/opt/m2repo` is a pre-seeded, writable local Maven repository containing
  everything the build can possibly need, fully offline: the JUnit 5.11.4
  test stack, and the Maven plugin set pinned in the project (compiler
  3.12.0, surefire 3.2.5, jar 3.4.0, dependency, maven-enforcer-plugin
  3.4.1).
- The published artifacts on `/opt/m2repo` are (group `com.example`):
  - `formatter:1.0.0` — the filled-text API `format(String text, char fill)`
    (surrounds the text with two copies of the fill character each side).
  - `formatter:2.0.0` — a modernized release that **dropped** that method;
    it only offers `format(String)`.
  - `conventions:1.0.0` — pins `formatter:1.0.0` as a dependency and
    supplies the application-level fill character.
  - `greeter:2.0.0` — built against `formatter:1.0.0`'s filled-text API; its
    `greet(String name)` renders `||Hello, NAME!||`.
  - `lib-y:1.0.0` — declares `formatter:2.0.0` as a dependency.
- The sources of all five artifacts are shipped on disk at `/app/libsrc` in
  case you want to read them. Do not modify anything there or under
  `/opt/m2repo`.
- **Every** `mvn` command you run here must be offline against the seeded
  repository: `mvn -B -o -Dmaven.repo.local=/opt/m2repo <goals>`. Keep the
  `-o` and `-Dmaven.repo.local=/opt/m2repo` flags on every invocation; a
  bare `mvn` will try the network and hang instead of failing fast.
- The container runs single-CPU (`cpus = 1`): keep Maven's default
  single-fork, single-thread test execution. Do not enable parallel builds
  or parallel test forks.

## The project

`/app/service` is a normal Maven project (`src/main/java`,
`src/test/java`). Its `pom.xml` declares `lib-y:1.0.0` and `greeter:2.0.0`
as compile dependencies plus the JUnit test stack, pins the lifecycle
plugins, and declares `maven-enforcer-plugin:3.4.1` — declared but not yet
configured, because configuring it is part of your job.

Start by running:

```
cd /app/service
mvn -B -o -Dmaven.repo.local=/opt/m2repo verify
```

and read the failure carefully, then fix the build. The verification
section below defines exactly what "fixed" means; everything it demands
must be true of your final `/app/service`.

## Verification (what the verifier will check)

1. **Build is green and the tests really run.**
   The verifier first copies hidden test sources into
   `/app/service/src/test` — tests that exercise the same greeting /
   formatting API, harder — then runs `mvn -B -o -Dmaven.repo.local=/opt/m2repo verify`
   and parses the surefire reports: zero failures, zero errors, the shipped
   `GreetingTest` and both hidden suites must have genuinely executed.
   Consequence: deleting, weakening or commenting out the shipped tests, or
   "fixing" this by stubbing the libraries, cannot help you — the hidden
   tests compile against the real published artifacts and assert the real
   behaviour.

2. **One version of the library, the right one.**
   `mvn -B -o -Dmaven.repo.local=/opt/m2repo dependency:tree` must show
   exactly **one** version of `com.example:formatter` anywhere in the
   resolved graph, and that version must be `1.0.0`. (A thought: the
   greeter application code needs the filled-text API, which only 1.0.0
   has; 2.0.0 compiled into the graph is what kills the suite.)

3. **The fix is defended, structurally.**
   Your final project must carry a **maven-enforcer rule** so that the
   build fails if `com.example:formatter:2.0.0` can ever re-enter the
   dependency graph. The verifier proves this adversarially: it copies your
   project to a scratch directory, surgically restores the conflict (ties:
   undo exclusions of the formatter artifact, clear any
   dependencyManagement override for it, strip any direct formatter
   dependency, and re-add the `formatter:2.0.0` edge), then runs
   `mvn -B -o -Dmaven.repo.local=/opt/m2repo validate` and requires a
   **non-zero** exit. So your rule must be bound to the `validate` lifecycle
   phase and trip the moment the bad version is back on the graph — it must
   not wait for compilation or tests.

4. **Nothing outside `/app/service` changes.** Leave `/opt/m2repo`,
   `/app/libsrc` and the environment as you found them.

## Orientation (not a spoiler, just a map)

Get the lay of the graph first:

```
mvn -B -o -Dmaven.repo.local=/opt/m2repo dependency:tree -Dverbose
```

Maven's dependency resolution has a well-defined rule for deciding which of
two reachable versions wins, and the winner here is the one that breaks the
build. Your fix has to change which version the graph resolves — that change
lives in the build configuration (the pom), not in the Java sources. The
verifier will run entirely offline against the same repository, so whatever
you change must stay within the artifacts already seeded.

When you believe it is fixed, run the verifier's own commands yourself:

```
mvn -B -o -Dmaven.repo.local=/opt/m2repo verify
mvn -B -o -Dmaven.repo.local=/opt/m2repo dependency:tree
```

until both do the right thing, then think about what would happen if the
conflicting path came back tomorrow — requirement 3 is there to stop that
from ever being silent again.