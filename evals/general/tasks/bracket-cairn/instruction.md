# Nested test classes must run in a deterministic order

## Situation

`/app/src` is a fresh, pinned, shallow clone of the JUnit 5 framework repository
(`junit-team/junit5`), checked out at one specific upstream commit from August
2025. The tree is exactly the upstream code at that commit — bug included. It
is not a workspace you may re-initialise: no new commits, no history rewrite,
no remotes, no fetches (fetches would fail anyway: there is no network).

The toolchain is already installed and configured:

- JDK 24.0.2 (Temurin) at `/opt/jdk-24.0.2+12` — the build's default Java
  toolchain and the Gradle daemon JVM (the repository's
  `gradle/gradle-daemon-jvm.properties` pins `toolchainVersion=24`). `JAVA_HOME`
  points there and `JDK24` is exported for Gradle's toolchain auto-detection
  (`org.gradle.java.installations.fromEnv`).
- JDK 21 (apt, `/usr/lib/jvm/java-21-openjdk-amd64`, exported as `JDK21`) and
  JDK 25.0.4.1 (Temurin, `/opt/jdk-25.0.4.1+1`, exported as `JDK25`) for the few
  build tasks in the dependency closure that need them.
- Gradle 9.0.0 through the project's own checked-in wrapper (`./gradlew`; the
  wrapper distribution is SHA256-pinned by the wrapper itself). All
  third-party dependencies are already downloaded, and the tree has already
  been built and its reflection-utilities test class executed once, so Gradle
  invocations are fast and incremental.
- **There is no network at trial time.** `git fetch`, plugin resolution and
  dependency downloads will not work. Run Gradle with `--offline` and it will
  not even try. Everything you need is in the image.

## The bug

Some test suites declare several nested test classes inside a single enclosing
test class. When the framework enumerates the nested classes of an enclosing
type it asks the JVM, and the JVM is explicitly allowed to return declared
classes in any order — the Javadoc of `Class.getDeclaredClasses()` states that
"the order in which the inner classes of a class are returned is unspecified".
Different JDK versions and different machines therefore return the nested
classes in different orders, so the same suite can list or run its nested
classes in one order in one environment and a different order in another.
Output-based comparisons and any order-sensitive logic become
non-deterministic across JDKs and machines.

In this checkout, the platform commons library exposes manifestly deterministic
ordering for every other reflection result it enumerates — observe how the same
library returns the declared methods and declared fields of a class: a stable
order computed from the fully qualified name, comparing `String.hashCode()` of
the name first, with lexicographic `compareTo` as the tie-breaker (see the
library's "default method sorter" / "default field sorter" and the
`toSortedMutableList` helper they share). The one enumeration that still comes
back in raw JVM reflection order is the nested-class enumeration behind
`findNestedClasses(Class, Predicate)` and `streamNestedClasses(Class,
Predicate)` (each also exists with a cycle-error-handling overload), which
several components use to enumerate the nested classes of an enclosing type.

## Reproducing

Drive your work with the project's own test runner, exactly like this (the same
command is available as `/app/run_tests.sh` and must stay green — do not break
it):

```
cd /app/src && ./gradlew :platform-tests:test \
  --tests "org.junit.platform.commons.util.ReflectionUtilsTests" \
  -Ptesting.enableJaCoCo=false --offline
```

(add `--tests "org.junit.platform.commons.support.ReflectionSupportTests"` to
also run the support facade's tests; both classes pass at the pinned commit).

To observe the bug, write a small scratch test under
`platform-tests/src/test/java/...` that asks the framework for the nested
classes of an enclosing type that declares several nested classes — for
instance `findNestedClasses(SomeType.class, c -> true)` mapped to names with
`Class::getSimpleName` — and run it with the command above, adding `--tests`
for your scratch class. The order you get back is whatever the JVM felt like
returning; on another JDK it would be a different order. **Delete your scratch
test again before you finish**: the final tree must contain no new or changed
test files.

## What the fix must satisfy

Make both entry points deterministic and keep every existing behaviour:

1. Nested classes declared in the *same* enclosing class or interface must be
   returned in the same ordering convention the library already uses for the
   methods and fields of a class: compare each class's fully qualified name
   (`Class.getName()` — note fully qualified, e.g. `org.example.Outer$Nested`,
   not the simple name), first by `String.hashCode()`, then lexicographically
   with `String.compareTo` as the tie-breaker.
2. The relative grouping by declaring type must not change: the nested classes
   declared by the type being searched come first (in deterministic order),
   then — when inherited — the nested classes of its superclass, then of its
   implemented interfaces, each group internally in the deterministic order
   described above.
3. A type declaring zero or one nested class behaves exactly as before.
4. The tree's own reflection-utilities tests and the support facade's tests
   keep passing, and nothing else in the tree changes.

The verdict is made by the verifier, which runs the framework's own regression
test for this bug plus hidden cases over inputs of its own. A fix that orders
nested classes by any other rule — plain alphabetical order or raw JVM order —
fails those checks.

## Constraints

- The clone at `/app/src` is the deliverable: change only the minimal
  production code the fix needs, in place. Do not add, remove or modify any
  other file in the tree (no new tests, no build-file edits, no `.git`
  mutations of any kind).
- `/opt/golden`, `/tests` and `/solution` are harness-owned — do not read or
  modify them.
- No network, no `git` mutations, no `-PjavaToolchain.version` (that flag
  breaks the project's NullAway nullability check). Everything you need is
  already in the image.

## What the verifier checks

1. Tree provenance: still at the pinned upstream commit, no fix commit present
   in the object store, no tracked file modified outside the minimal production
   source, no new files under the commons or platform-tests source trees, and
   the buggy production code actually changed.
2. The framework's own regression test for this bug — extracted from the
   upstream fix revision at image-build time into the harness-owned
   `/opt/golden` — passes against your tree, with the whole
   `ReflectionUtilsTests` class green in the same run.
3. The tree's own `ReflectionUtilsTests` and `ReflectionSupportTests` classes
   pass with your fix applied and their upstream content untouched.
4. Hidden cases exercise the same code path from inputs the upstream regression
   test does not use: a different multi-nested-class input, a predicate-filtered
   query, an inheritance chain, an interface declaring nested classes, the
   stream API and the support facade's entry points.

Deliverable: the repaired `/app/src` tree.