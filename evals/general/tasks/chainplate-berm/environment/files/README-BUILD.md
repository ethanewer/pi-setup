# Build and test notes for /app/src (netty, pinned parent commit)

Everything below works **fully offline**. The image baked the Maven local
repository (all dependencies + installed SNAPSHOT artifacts of the modules
below) into `/opt/m2` and pre-compiled the dependency modules' outputs.

## Modules you can touch without a network

The module where zlib decompression lives is `codec-compression`; its
dependency closure (`common`, `buffer`, `transport`, `codec-base`) is already
built, installed in `/opt/m2`, and its `target/classes` are prebuilt from the
pinned parent sources. `codec-compression`'s own output is NOT prebuilt:
compile it yourself, and any change you make to it is picked up on the next
compile.

Maven is configured through `MAVEN_OPTS` (see `env`): JVM heap `-Xmx5g`, local
repository `/opt/m2`. Add `-o` to every `mvn` invocation.

## Compile a scratch Java file against the module's classes

Build the module first, then compile your scratch file against
`codec-compression/target/classes` plus the already-built dependency module
classes:

```bash
cd /app/src
mvn -o -pl codec-compression compile -Dcheckstyle.skip=true
CP="codec-compression/target/classes:codec-base/target/classes:buffer/target/classes:common/target/classes:$(find /opt/m2 -name '*.jar' | tr '\n' ':')"
javac -cp "$CP" -d /tmp /tmp/Repro.java
java -cp "/tmp:$CP" Repro
```

The `find /opt/m2 -name '*.jar'` suffix is needed at *runtime* only: the uncompressed public API pulls in jctools and friends beyond the four modules' own classes, and everything is already in `/opt/m2` (the trial is offline, so this is also the only classpath that works).

## Run the module's own tests (surefire 3.5.3, JUnit 5)

```bash
cd /app/src
mvn -o -pl codec-compression test -Dtest=JdkZlibDecompressorTest \
    -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true
```

`surefire.failIfNoSpecifiedTests=false` is required with surefire 3.5.3 (`-DfailIfNoTests=false` is ignored).
Reports land in `codec-compression/target/surefire-reports/`.

## Useful navigation

- `grep -r "class JdkZlibDecompressor" codec-compression/src/main/java/`
- The `Decompressor` interface (status machine) sits next to it in the same
  package.
- `git status --porcelain` to see a dirty tree; `git diff` to see changes.

## Do not

- run `mvn` with network, or with a repository other than `/opt/m2`;
- modify `.git` (the clone is read-only by convention; it is a one-commit
  shallow clone at the pinned commit);
- leave scratch files inside `/app/src` (put them in `/tmp`); the graded
  tree is byte-compared against the pinned commit.