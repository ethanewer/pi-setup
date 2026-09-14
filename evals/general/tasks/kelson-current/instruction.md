# kelson-current

You are working inside a real open-source codebase: **netty** (`netty/netty`),
a high-performance network framework for Java, checked out at a pinned commit
in `/app/src` (the working tree starts clean at that commit). There is a bug
in this tree's **gzip codec** (the `codec-compression` module). Your job is
to find it, fix it in the working tree, and prove the fix with the project's
own test tooling. You are deliberately **not** told which class or method to
change: localising the bug is part of the task.

## Environment

- OpenJDK 21 and Maven 3.8.7 are installed and on `PATH` (`mvn`, `java`,
  `javac`, `git`).
- **There is no network** in this container, but Maven works fully offline:
  the local repository at `/opt/m2/repository` (wired in as the global
  Maven local repository) was warmed at image build time by building and
  installing the `codec-compression` module and everything it depends on
  (`codec-base`, `codec`, `transport`, `buffer`, `common`, …). All plugins
  are cached. Always run `mvn` with the `-o` flag; without it, Maven cannot
  reach Central and may error out instead of building.
- `cpus = 1`: one vCPU. Do not launch parallel builds, and do not tune the
  Maven thread counts up.
- The tree at `/app/src` is shallow (one commit) and detached; do not
  commit, fetch, or otherwise modify `.git`. Your changes must stay in the
  working tree.
- A compiled `target/` directory for the module already exists from the
  build-time warm pass; incremental rebuilds are fast.
- Do not touch anything under `/tests`, `/solution`, `/opt/golden`,
  `/opt/prefix`, `/opt/pins` or `/opt/m2` — that is evaluation machinery and
  the warm caches.

## The bug (user-visible symptom)

Some gzip producers store metadata in the gzip *header*: the format allows a
stream to carry an "extra field" after the fixed 10-byte header (the `FEXTRA`
flag in the gzip header, RFC 1952). BGZF files (the block-compressed BAM
format) and a few archival tools rely on this. Netty's gzip codec cannot
decode such streams: a perfectly valid gzip stream that carries an extra
field throws a `DecompressionException` ("decompression failure") as soon as
the compressed body is reached and **no output is produced at all**, even
though the very same bytes decompress cleanly with the JDK's own gzip reader
(`java.util.zip.GZIPInputStream`). There is a secondary symptom: when
several gzip members are concatenated into one stream and the first member
carries an extra field, later members fail to decode too, even when they are
ordinary gzip streams.

Ordinary gzip output never sets this header flag, which is why the bug is
invisible in everyday use: only unusual-but-valid producers are affected.
The correct behaviour is that the codec decompresses such streams to exactly
the original bytes, just as the JDK reader does.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom above. Its contract:

   - It runs one JUnit test class that you create **as a new file** in the
     module's test package:
     `/app/src/codec-compression/src/test/java/io/netty/handler/codec/compression/`
     (JUnit 5, `org.junit.jupiter`). The test must hand-craft a valid gzip
     byte stream whose header carries an extra field, sanity-check it with
     the JDK's own `GZIPInputStream`, then feed it through the codec's gzip
     decoder and assert the decompressed bytes match exactly.
   - It runs that test through the project's own test runner, fully
     offline. Use exactly this command shape (plus the `-Dtest=…` filter
     for your own test class name):
     ```
     mvn -o -pl codec-compression test \
         -Dtest=<YourTestClassName> \
         -Dsurefire.failIfNoSpecifiedTests=true \
         -Dcheckstyle.skip=true \
         -Dxml.format.skip=true \
         -Dlicense.skip=true
     ```
   - It prints the full Maven/surefire output and **nothing else**.
   - It exits 0 **if and only if** the reproduction test passed (the
     Maven build succeeded and surefire reports `Tests run: N, Failures: 0,
     Errors: 0` with `N >= 1`); it exits nonzero otherwise.
   - It must work no matter what the current working directory is when it
     is invoked.

   On the **unfixed** tree this script must fail: the extra-field stream
   cannot be decoded, surefire reports the failing test, and the script
   exits nonzero. Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes, and confirm the fix is real by re-running the
   same reproduction after a clean rebuild of the module (delete
   `codec-compression/target` first so your compiled classes are rebuilt
   from your sources). Fix the mechanism, not just one input: the same
   defect is reachable with other extra-field sizes, other bytes in the
   header (see Grading), and concatenated members. Do not merely special-
   case a wrapper — the regression test the grader runs exercises the codec
   directly.

3. **Break nothing else.** The module's existing test suite must stay
   green: in particular the existing gzip/zlib decoder tests must still
   pass unchanged. The problem must be fixed such that ordinary gzip
   streams (no extra field) decode exactly as before.

4. **Keep the tree clean.** Except for the single source file where the
   bug lives, and your one new reproduction test class, every file in
   `/app/src` must stay byte-identical to the pinned commit. Do not add,
   move, delete, rename or reformat any file; if you create scratch files
   to investigate, delete them before you finish; make no commits; do not
   modify any build metadata (`pom.xml` files, etc.). The grader compares
   the actual bytes of every tracked file against the pinned commit, so
   cosmetic side-changes also fail. Your two authored files `/app/repro.sh`
   and `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   where it came from, what you changed, and how you verified the fix.

## Working loop (recommended)

1. Craft your reproduction stream first (build the gzip bytes by hand, or
   take a normal gzip stream and splice the extra field into its header),
   and confirm it fails with the unfixed code. Reread the spec of the gzip
   header in RFC 1952 (in particular where the extra-field length lives and
   in which byte order it is stored) before you start looking for the
   defect.
2. Localise the bug by reading the code: find the codec-compression gzip
   path, and trace how the header is parsed before the compressed body is
   handed to the inflater. Pay attention to how the code remembers whether
   there is an extra field and how far into the stream it has to skip
   before the compressed body starts — and what state survives between
   concatenated members.
3. Fix with the smallest possible change in that one source file, rebuild
   (delete `codec-compression/target`, then `mvn -o …`), and confirm
   `/app/repro.sh` passes.
4. Prove nothing else broke: run the module's gzip/zlib test classes (at
   least `JdkZlibTest`) with
   `mvn -o -pl codec-compression test -Dtest=JdkZlibTest -Dsurefire.failIfNoSpecifiedTests=true -Dcheckstyle.skip=true -Dxml.format.skip=true -Dlicense.skip=true`.
   Every pre-existing test must pass.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree
   (plus your new reproduction test class in the module test package).
2. `/app/repro.sh` — your own failing reproduction, per the contract above
   (executable: `chmod +x /app/repro.sh`).
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails — the only new file allowed in the tree is
  your reproduction test class in the module test package);
- require `/app/repro.sh` and `/app/summary.md` to exist, be executable
  (`repro.sh`), and be non-empty;
- rebuild the module from your tree (your compiled `target/` is deleted
  first so nothing you planted there survives), then run your
  `/app/repro.sh` against the repaired tree (must pass: exit 0 and a clean
  surefire test summary) **and** against the pristine pre-fix state (the
  original buggy decoder source, baked into the image at `/opt/prefix`:
  your reproduction must FAIL there, proving the symptom is real and your
  reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) and run it together with the module's pre-existing
  gzip/zlib tests: all must pass;
- run additional authored test cases that reach the same codec path from
  inputs the upstream test does not use (a large extra field whose length's
  high byte is nonzero, an extra field whose length's low byte is zero, and
  concatenated members mixing an extra field plus a file name with a plain
  member); each must decode byte-for-byte.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.