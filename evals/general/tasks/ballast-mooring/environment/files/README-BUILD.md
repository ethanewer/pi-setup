# Build and test notes for /app/src (netty, pinned parent commit)

Everything below works **fully offline**. The image baked the Maven local
repository (all dependencies + installed SNAPSHOT artifacts of the modules
below) into `/opt/m2` and pre-compiled the module outputs.

## Modules you can touch without a network

The module where HTTP-date parsing lives is `codec-base`; its dependency
closure (`common`, `buffer`, `transport`) is already built and installed.
`codec-compression` is also installed (it is part of the reactor build).

Maven is configured through `MAVEN_OPTS` (see `env`): JVM heap `-Xmx5g`, local
repository `/opt/m2`. Add `-o` to every `mvn` invocation.

## Compile a scratch Java file against the module's classes

`codec-base`'s compiled output is NOT shipped prebuilt (the image starts the
tree from source so the bug is live until you rebuild it); build the module
first, then compile your scratch file against `codec-base/target/classes`
plus the already-built `common/target/classes`:

```bash
cd /app/src
mvn -o -pl codec-base compile -Dcheckstyle.skip=true
javac -cp codec-base/target/classes:common/target/classes -d /tmp /tmp/Repro.java
java -cp /tmp:codec-base/target/classes:common/target/classes Repro
```

## Run the module's own tests (surefire 3.5.3, JUnit 5)

```bash
cd /app/src
mvn -o -pl codec-base test -Dtest=DateFormatterTest \
    -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true
```

`surefire.failIfNoSpecifiedTests=false` is required with surefire 3.5.3 (`-DfailIfNoTests=false` is ignored).
Reports land in `codec-base/target/surefire-reports/`.

## Useful navigation

- `grep -r "class DateFormatter" codec-base/src/main/java/`
- `git status --porcelain` to see a dirty tree; `git diff` to see changes.

## Do not

- run `mvn` with network, or with a repository other than `/opt/m2`;
- modify `.git` (the clone is read-only by convention; it is a one-commit
  shallow clone at the pinned commit);
- leave scratch files inside `/app/src` (put them in `/tmp`); the graded
  tree is byte-compared against the pinned commit.