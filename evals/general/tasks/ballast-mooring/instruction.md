# ballast-mooring

You are working inside a real open-source codebase: **Netty**
(`netty/netty`), the high-performance networking library, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's HTTP-date parsing. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own build and test
tooling. You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- JDK 21 and Maven 3.8.7 are installed and on `PATH` (`java`, `javac`,
  `mvn`, `git`).
- **There is no network** in this container. Everything Maven could need is
  already baked in: the module closure (`common`, `buffer`, `transport`,
  `codec-base`, `codec-compression`) was built and `install`ed at image build
  time into the shared local repository `/opt/m2` (pointed at by the
  `MAVEN_OPTS` environment variable). Add `-o` to every `mvn` invocation; a
  Maven run that tries to download anything fails.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is a shallow (one commit) detached clone; do not
  commit, fetch, or otherwise modify `.git`. Scratch files belong in `/tmp`,
  never inside `/app/src`.
- `/app/README-BUILD.md` summarises the module layout and the exact commands
  that work offline.

## The bug (user-visible symptom)

Netty's `DateFormatter` parses HTTP dates, including the `Expires` attribute
of a `Set-Cookie` header. RFC 6265 does not give attribute order a meaning,
so the expiration date may appear anywhere among the cookie attributes — yet a
cookie whose `Expires` value is followed by other attributes silently loses
its expiration: the very same date text parses fine on its own and fine when
it is the last attribute of the header, but when the date substring is
followed by more attributes, parsing returns `null`. The cookie then degrades
to a session cookie, and no error is ever raised.

Reproduce it with the public API. Because the parse is given a slice of a
longer header, use the `CharSequence` / `start` / `end` overload:

```bash
cd /app/src
cat > /tmp/Repro.java <<'EOF'
import io.netty.handler.codec.DateFormatter;
import java.util.Date;
public class Repro {
    public static void main(String[] args) {
        String header = "Set-Cookie: foo=bar; Expires=Sun 08:49:37 06 Nov 1994; Path=/";
        int start = header.indexOf("Sun 08");
        int end = header.indexOf("; Path=/");
        Date parsed = DateFormatter.parseHttpDate(header, start, end);
        System.out.println("parsed: " + parsed);
    }
}
EOF
mvn -o -pl codec-base compile -Dcheckstyle.skip=true   # module output not prebuilt; compiles the tree from source
javac -cp codec-base/target/classes:common/target/classes -d /tmp /tmp/Repro.java
java -cp /tmp:codec-base/target/classes:common/target/classes Repro
```

On the buggy tree this prints `parsed: null`. The correct behaviour is to
print `parsed: Sun Nov 06 08:49:37 UTC 1994` — the same date literal,
`Sun 08:49:37 06 Nov 1994`, parses as a standalone string (also try it), so
the defect is specific to slicing: the token that completes the parse ends at
the slice boundary, and something about how the trailing token is finished
lets the bytes after the boundary leak into it.

## Requirements

1. Fix the tree so that the reproduction above prints
   `parsed: Sun Nov 06 08:49:37 UTC 1994` (and exits cleanly), in the module's
   own compiled classes — i.e. build the module with `mvn -o -pl codec-base`
   and re-run the repro against `codec-base/target/classes`. Fix the
   mechanism, not this one input: any HTTP date whose final token ends exactly
   at the requested `end` (year-last, time-last, dash-separated two-digit
   years, non-zero `start`, whatever follows `end` in the `CharSequence`)
   must parse correctly. Do not just trim the input before parsing — the API
   contract is that the caller chooses the range.
2. Everything else must keep working exactly as before: full-string parses
   (no explicit range), all supported date formats, invalid inputs, and the
   rest of the `codec-base` module's tests must stay green. The module's own
   existing `DateFormatterTest` currently passes and does **not** cover this
   slicing defect, so passing it alone proves nothing — use your own
   reproduction.
3. The graded tree must be byte-identical to the pinned commit except for the
   **single source file where the bug lives** (the scanner class you discover
   by localising it). Do not add, move, delete, rename or reformat any file;
   if you create scratch files to investigate, delete them before you finish;
   make no commits; do not modify any test, `pom.xml` or metadata file. The
   grader compares every file's bytes against the pinned commit's own blobs,
   so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above (scratch files in `/tmp` only).
2. **Localise**: the API is `DateFormatter.parseHttpDate(CharSequence, int,
   int)`; find that class in the tree
   (`grep -r "class DateFormatter" codec-base/src/main/java/`). Read its
   token scanner carefully: the loop `for (i = start; i < end; i++)` collects
   tokens, terminates each one with the delimiter position, but then has a
   separate branch for the *final* token — the one running up to `end`.
   Compare what range that branch passes when it parses the token with how
   the loop terminates in-range tokens. That is where the slice boundary is
   lost. Understand *why* the absorb follows bytes before you patch.
3. **Fix** with the smallest possible change in that one file; rebuild with
   `mvn -o -pl codec-base compile` (or `test`); re-run the repro; it must
   print the date and exit 0.
4. **Prove nothing else broke** with the project's own runner (surefire
   3.5.3, JUnit 5; `-Dsurefire.failIfNoSpecifiedTests=false` is required —
   the old `-DfailIfNoTests=false` is ignored):

   ```bash
   mvn -o -pl codec-base test -Dtest=DateFormatterTest \
       -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true
   mvn -o -pl codec-base test -Dtest=Base64Test,JsonObjectDecoderTest,LineEncoderTest \
       -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true
   ```

   Reports land in `codec-base/target/surefire-reports/`.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression test** for this bug (upstream added it
  with the fix, so it is not in this tree; the image baked it at
  `/opt/golden`) into the `codec-base` test suite, and run it together with
  additional hidden cases — other Set-Cookie-shaped headers, other date
  formats and token orderings, other slice geometries — through `mvn -o -pl
  codec-base test`; all must pass;
- run a selection of the project's own existing `codec-base` tests, which
  must stay green.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.