# calm-canyon — restore, rebuild, scaffold

You are an SRE working in `/app` on the `hydrawatch` stream-distribution service and
its companions. Complete **four** independent deliverables. Everything lives in
`/app`; tests run against hidden data you will never see, so follow the contracts
exactly and make every tool generic and correct.

You have a full Linux toolbox: `git`, `curl`, `maven`/`mvn`, OpenJDK 17,
`python3` (+ `pip`), the Lean toolchain (`lean`/`lake`/`elan`), and the protobuf
code generator. You may install packages. **Never read or modify `/tests`, and
never hard-code a result that the task asks you to compute** — the verifier
re-runs your tools on fresh inputs and your computed outputs must generalize.

---

## Deliverable 1 — a generic source release fetch+extract tool (`/app/fetch_src.sh`)

A "release mirror" is a plain static HTTP directory publishing three files:

* `current.txt` — a single line naming the release archive to fetch, e.g.
  `hydrawatch-src-2029.55.0.tgz`.
* `checksum.sha256` — one line of the form `<64-hex>  <archive-filename>` giving
  the SHA-256 of that archive.
* the archive itself (a `tar.gz` packed source tree).

Write an executable script **`/app/fetch_src.sh`** with the exact signature:

```sh
/app/fetch_src.sh <mirror_root_url> <dest_dir>
```

Given a mirror root (a URL whose directory listing serves the three files above),
it must:

1. Read `current.txt` to learn the archive name.
2. Download the archive and `checksum.sha256`.
3. **Verify the downloaded archive's SHA-256 matches the published checksum.**
   If it does not match — or if no checksum line exists for that archive — the
   script MUST fail: exit non-zero, print an error, and **leave `<dest_dir>`
   absent/untouched** (remove it if it created anything).
4. On a valid checksum, extract the archive into `<dest_dir>`.
5. **Verify the extracted tree is intact.** The archive embeds a
   `MANIFEST.json` at its root of the shape
   `{"release": "<ver>", "files": {"<relpath>": "<sha256>", ...}}`. Every file
   listed by the manifest must be present at exactly that path with that exact
   SHA-256; there must be no extra files beyond the manifest listing (except
   `MANIFEST.json` itself). If any file is missing, extra, or hash-mismatched,
   the script MUST fail: exit non-zero, print an error, and remove `<dest_dir>`
   so nothing is left behind.
6. Always require the distro metadata shard `debian/control` to be present under
   `<dest_dir>`; if missing, fail as above.

The tool must be robust to the **two failure shapes** described above (bad
checksum store; tampered/mismatched tree). Exit codes do not need to be specific,
only non-zero on failure. A helper `bin/verify_extract.py` is included **inside**
the release payload (under `bin/`) that performs the manifest-vs-filesystem
integrity walk and returns non-zero on any divergence — your tool may call it.

### Apply the tool

Build the visible source store. The release mirror is bundled in
`/app/payload/` (a template of the exact layout above). Serve it as a static HTTP
mirror on `127.0.0.1:8811` (e.g. `python3 -m http.server 8811 --bind 127.0.0.1
--directory /app/payload`), then run

```sh
bash /app/fetch_src.sh http://127.0.0.1:8811 /app/src
```

so `/app/src` will be an intact hydrawatch source tree. `/app/src` is a
**buildable copy**: you may edit it for the rebuild in Deliverable 2. This
restored tree (with mutable working files) is Deliverable 1.

---

## Deliverable 2 — scoped Maven distribution rebuild

`/app/src` is a Maven project (`pom.xml`, single-module
`io.hydra:hydrawatch`). It builds a self-contained jar (`mvn -B package`
produces `target/hydrawatch.jar`) whose main class `HydraREST` runs a tiny
HTTP service on a port from `HYDRA_PORT` (default `8790`). It reads a gauge file
from `HYDRA_LIVE` (default `/app/flink_scoped_build/live.json`).

The service exposes three endpoints that form its **public contract. Their
response JSON / behavior MUST remain identical across a rebuild**:

* `GET  /api/v1/health`      → `{"status":"ok"}`
* `POST /api/v1/upload`       → `{"accepted":true,"bytes":<n>}` (n = request body byte length)
* `GET  /api/v1/metric/live` → `{"live":<gauge>}`

The **gauge** is bugged. The legacy source in
`src/main/java/io/hydra/watch/MetricsEngine.java` applies an obsolete
**penalty term**: for every negative delta it adds `7` extra onto the running
total. The demanded behavior is a pure **net-flux** gauge, i.e. the simple sum
of every signed delta recorded in the live file (`{"deltas":[12,-4,15, ...]}`,
a tolerant JSON array that may be empty or whitespace-padded). Remove the
penalty term — a build where the gauge still returns the penalized value FAILS.

Plan:

1. Edit `/app/src` so `MetricsEngine.live()` is the pure sum (no `+7` term).
2. Rebuild the scoped distribution: `cd /app/src && mvn -B package`, capturing
   all output to **`/app/build.log`**. The log must contain a Maven
   `BUILD SUCCESS` line when completed.
3. Suspect the rebuilt jar and the runtime seed into the distribution dir
   **`/app/flink_scoped_build/`**, so it is self-contained:
    * the jar  at `/app/flink_scoped_build/hydrawatch.jar`,
    * `/app/flink_scoped_build/live.json` (the tick-deltas consumed by the gauge),
    * a `start.sh` tidy runner that sets `HYDRA_LIVE=/app/flink_scoped_build/live.json`
      (and a `HYDRA_PORT` defaulting to `8790`) and execs
      `java -jar /app/flink_scoped_build/hydrawatch.jar`.
4. Start the patched service on the expected local port `8790` (leave it
   running for probing) and write a probe snapshot to **`/app/behavior_check.log`**
   containing the three endpoints' responses (e.g.
   `health: ...`, `upload_abc: ...`, `live: ...`).

The verifier will recompile deliverable source via Maven, start an instance
of the shipped jar, and assert (a) the unrelated endpoints `health` / `upload`
are unchanged and (b) the gauge equals the pure net sum of the deltas in the
shipped `live.json`.

---

## Deliverable 3 — a Lean lake project that pulls a math library

A bundled math library already exists at `/app/mlib` (a Lake package named
`math` with `lean_lib Math`; it defines helpers in `Math.Sum`, e.g.
`doubleSum`, theorems `doubleSum_eq`, `add_comm_own`, `sq_pos`).

Scaffold a new Lean lake project **`/app/lake_project`** that **declares a
dependency on that bundled math library and resolves it**. Concretely:
`lakefile.lean` must declare the project (e.g. `package basin`) and a
`require "math" from "../mlib"` path dependency. When built, the project must
start in the working tree. Provide at least one source file (e.g.
`Basin.lean` importing a module `Basin.Probe`) whose theorems actually call
into the pulled math library, and build it:

```sh
cd /app/lake_project && lake build <your-lib>
```

Then copy a newly-built olean (the compiled product of your theorem module) to
**`/app/math_check.olean`**. The math library is a path dependency (no network
fetch needed for it), and the library resolving under this project is part of
what the verifier checks.

The verifier may drop an **additional hidden theorem file** into your project's
library directory (importing `Math.Sum` and using the bundled helpers) and
re-run `lake build`; it must compile against the pulled library. So do not
commit snapshot builds or assume a fixed set of source files — the library 
dependency must resolve for any compatible new file.

---

## Deliverable 4 — generate Python bindings from a proto, and a client

Write a generic binding generator **`/app/gen_proto.py`** with signature:

```sh
python3 /app/gen_proto.py <proto_file> <out_dir>
```

It must run `grpc_tools.protoc` (or equivalent) to emit, into `<out_dir>`, the
two Python binding modules derived from the proto filename:
`<stem>_pb2.py` and `<stem>_pb2_grpc.py` (create `<out_dir>` if needed). It must
exit 0 only when **both** modules have actually been produced; anything else
must exit non-zero (and it must work for any input proto, not just a fixed one).

A proto file with a service and messages is provided at
**`/app/telemetry.proto`**. Generate the bindings with

```sh
python3 /app/gen_proto.py /app/telemetry.proto /app/gen
```

### Client

Write **`/app/proto_client.py`** — a small CLI that imports your generated
bindings from `/app/gen`, constructs one `Sample` message (`id=7`,
`label="fjord"`, `value=1.25`), serializes it and reparses it, and prints a line
confirming the round-trip identity (e.g. `proto round-trip OK (id=7 label=fjord)`).
The client must use the **literal `/app/gen`** bindings.

The verifier will (a) re-run both generator and client, (b) regenerate bindings
from a **different hidden `.proto`** into a fresh output dir and confirm the
generated modules compile and produce a working round-trip message.

---

## Constraints & contract summary (read before starting)

* Work only under `/app`. Final literal paths for the verifier:
  `/app/fetch_src.sh`, `/app/src/`, `/app/build.log`,
  `/app/flink_scoped_build/`, `/app/behavior_check.log`,
  `/app/lake_project/`, `/app/math_check.olean`, `/app/gen/`,
  `/app/gen_proto.py`, `/app/proto_client.py`.
* Never read `/tests/`; their contents are mounted only at verification.
* Do NOT modify `/app/mlib` or `/app/telemetry.proto`.
* The hidden cases probe at least: a healthy mirror, a **bad-checksum mirror**
  (archive exists but its published checksum is wrong) and a **tampered tree**
  (archive whose embedded MANIFEST.json listing disagrees with its
  contents). Your fetch script must handle these, and your build/scaffold/client
  tools must be generic (accept arbitrary mirror URLs, proto files, and project
  files).
* The REST contract shapes are frozen; changing them breaks Deliverable 2.
## Definition of done

All of the above deliverables exist with correct behavior, the rebuilt service
reports the pure net-flux gauge while leaving `health`/`upload` untouched, the
lake project compiles against the pulled library, and the bindings round-trip.