# chainplate-berm

You are working inside a real open-source codebase: **Netty**
(`netty/netty`), the high-performance networking library, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's zlib decompression. Your job is to find it, fix it in the
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

Netty's zlib decompression code path can silently lose the end of a stream.
When the compressed payload is *highly compressible* — for example a long run
of a single repeated byte, which compresses to hundreds or thousands of times
fewer bytes than it expands to — decompression stops early: the caller is
told there is no output to take, and when the input is then declared complete
the tree reports `DecompressionException: Compressed stream ended before the
end-of-stream marker`, even though the stream was complete and valid. No data
corruption error is raised; the tail of the decoded data is simply dropped.
The exception surfaces not just in the low-level API but in any pipeline that
decompresses such a payload.

Two observations narrow it down:

- Content wrapped in a zlib or gzip header usually escapes the failure,
  because those formats' trailers keep a byte count above zero until the
  inflater has finished. The failure is characteristic of *raw* deflate
  streams (no wrapper), including the wrapper-negotiating mode that silently
  resolves to raw deflate.
- The failure needs an extreme compression ratio: a payload of about 100000
  repeated bytes reliably triggers it; a few hundred bytes of plain text does
  not.

Reproduce it with the public API. `JdkZlibDecompressor` is built through a
builder with a configurable `ZlibWrapper`:

```bash
cd /app/src
cat > /tmp/Repro.java <<'EOF'
import io.netty.buffer.ByteBufAllocator;
import io.netty.buffer.CompositeByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.handler.codec.compression.Decompressor;
import io.netty.handler.codec.compression.JdkZlibDecompressor;
import io.netty.handler.codec.compression.ZlibWrapper;
import java.io.ByteArrayOutputStream;
import java.util.Arrays;
import java.util.zip.Deflater;
import java.util.zip.DeflaterOutputStream;
public class Repro {
    public static void main(String[] args) throws Exception {
        byte[] expected = new byte[100000];
        Arrays.fill(expected, (byte) 'a');
        // deflate WITHOUT wrapper (raw), using the JDK so the input is known-good
        Deflater deflater = new Deflater(Deflater.DEFAULT_COMPRESSION, true);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (DeflaterOutputStream dos = new DeflaterOutputStream(out, deflater)) {
            dos.write(expected);
        }
        byte[] compressed = out.toByteArray();
        System.out.println("compressed " + expected.length + " bytes to " + compressed.length + " bytes");
        ByteBufAllocator alloc = ByteBufAllocator.DEFAULT;
        try (Decompressor d = JdkZlibDecompressor.builder()
                .wrapper(ZlibWrapper.NONE).build(alloc)) {
            d.status();
            d.addInput(Unpooled.wrappedBuffer(compressed));
            CompositeByteBuf result = alloc.compositeBuffer();
            try {
                for (;;) {
                    switch (d.status()) {
                        case NEED_OUTPUT:
                            result.addComponent(true, d.takeOutput());
                            break;
                        case COMPLETE:
                            byte[] got = new byte[result.readableBytes()];
                            result.readBytes(got);
                            System.out.println("decompressed " + got.length + " bytes");
                            System.out.println(Arrays.equals(expected, got)
                                    ? "ROUNDTRIP-OK" : "ROUNDTRIP-MISMATCH");
                            return;
                        default:
                            d.endOfInput();
                    }
                }
            } finally {
                result.release();
            }
        }
    }
}
EOF
mvn -o -pl codec-compression compile -Dcheckstyle.skip=true   # module output not prebuilt; compiles the tree from source
CP="codec-compression/target/classes:codec-base/target/classes:buffer/target/classes:common/target/classes:$(find /opt/m2 -name '*.jar' | tr '\n' ':')"
javac -cp "$CP" -d /tmp /tmp/Repro.java
java -cp "/tmp:$CP" Repro
```

On the buggy tree this throws `DecompressionException: Compressed stream
ended before the end-of-stream marker` and the tail (a large part of the
100000 bytes) never comes out. The correct behaviour is to print
`decompressed 100000 bytes` and `ROUNDTRIP-OK`. The very same compressed
buffer, decompressed with the JDK's own `Inflater(nowrap=true)`, yields all
100000 bytes, so the input is valid — the loss is in this tree.

## Requirements

1. Fix the tree so that the reproduction above prints `ROUNDTRIP-OK` (and
   exits cleanly), in the module's own compiled classes — i.e. build the
   module with `mvn -o -pl codec-compression` and re-run the repro against
   `codec-compression/target/classes`. Fix the mechanism, not this one input:
   the same class of payload — other repeated bytes, larger and smaller
   payloads, data fed to the decompressor in small chunks, and the
   wrapper-negotiating mode (the `ZlibWrapper` value that decides between
   zlib and raw by sniffing the first bytes) when it resolves to raw deflate —
   must all decompress fully. Do not make `endOfInput()` silently swallow
   errors: genuinely truncated streams must still be rejected exactly as
   before.
2. Everything else must keep working exactly as before: zlib- and
   gzip-wrapped streams, truncated-stream detection, footer/CRC checking, and
   the rest of the `codec-compression` module's tests must stay green. The
   module's own existing tests currently pass and do **not** cover this
   tail-loss defect, so passing them alone proves nothing — use your own
   reproduction.
3. The graded tree must be byte-identical to the pinned commit except for the
   **single source file where the bug lives** (the decompressor implementation
   you discover by localising it). Do not add, move, delete, rename or
   reformat any file; if you create scratch files to investigate, delete them
   before you finish; make no commits; do not modify any test, `pom.xml` or
   metadata file. The grader compares every file's bytes against the pinned
   commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above (scratch files in `/tmp` only).
2. **Localise**: the entry point is the `JdkZlibDecompressor` class
   (`grep -r "class JdkZlibDecompressor" codec-compression/src/main/java/`).
   Read the `Decompressor` interface's contract in
   `codec-compression/src/main/java/io/netty/handler/codec/compression/`:
   `status()` reports which operation may make progress, `takeOutput()`
   produces output, `endOfInput()` must only ever be called when no more input
   is coming. Then read the decompressor's output path carefully: how does it
   decide the size of the buffer it hands to the JDK `Inflater`? What is that
   size derived from, and what does the code conclude from `Inflater`'s
   callbacks about whether more output may still be pending? Think about what
   those signals report when all input bytes have been consumed *but* a large
   amount of decoded data is still buffered inside the inflater. That is where
   the tail is lost. Understand *why* before you patch.
3. **Fix** with the smallest possible change in that one file; rebuild with
   `mvn -o -pl codec-compression compile` (or `test`); re-run the repro; it
   must print `ROUNDTRIP-OK` and exit 0.
4. **Prove nothing else broke** with the project's own runner (surefire
   3.5.3, JUnit 5; `-Dsurefire.failIfNoSpecifiedTests=false` is required —
   the old `-DfailIfNoTests=false` is ignored):

   ```bash
   mvn -o -pl codec-compression test -Dtest=JdkZlibDecompressorTest \
       -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true
   mvn -o -pl codec-compression test -Dtest=JdkZlibTest,ByteBufChecksumTest,DefensiveDecompressorTest \
       -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true
   ```

   Reports land in `codec-compression/target/surefire-reports/`.
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
  `/opt/golden`) into the `codec-compression` test suite, and run it together
  with additional hidden cases — payloads of other repeated bytes and sizes,
  chunked input feeding, and the sniffing wrapper mode resolving to raw
  deflate — through `mvn -o -pl codec-compression test`; all must pass;
- run a selection of the project's own existing `codec-compression` tests,
  which must stay green.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.