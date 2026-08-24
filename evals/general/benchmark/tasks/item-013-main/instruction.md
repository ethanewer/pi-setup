# Staged "certified C" toolchain build (c0)

In `/app/compcert-src` is the **source snapshot** of a CompCert-3.13.1-style
*staged* "certified C" front-end build called **c0**. It arrives **unbuilt** and
**with an incomplete host toolchain**. Your job is to bring the build up through
its stages, diagnose and clear the missing toolchain components, and reach the
finished, working `build/c0` artifact with all staged sub-artifacts present.

Read `/app/compcert-src/README.md` first. It documents the layout, the exact
`configure` → `make` stage sequence, the required host toolchain components, the
host-ABI constraint, and a self-check you must pass before finishing.

## What must be true when you finish

1. **Toolchain up:** The host has `gcc`, `ocamlc`, and `coqc` available (run
   `configure`, which probes for them). Anything missing must be diagnosed and
   installed. On Ubuntu the typical fix is `apt-get install -y ocaml coq`.
2. **Stages run:** `make all` (or its four stages, in order) must complete. The
   staged sub-artifacts `compcert-src/build/cert.checked` (from the Coq
   `verify` stage) and `compcert-src/build/oextract.checked` (from the OCaml
   `oextract` stage) must both exist. Do not manufacture them by hand.
3. **Wordsize correct:** `configure`'s architecture probe must settle on the
   intended **wordsize of 64** for the actual host ABI. The deployed header line
   in c0 output must say `; wordsize 64`.
4. **Backend builds and behaves:** `compcert-src/build/c0` must exist. Running
   `./build/c0 <input> <output>` must translate a supplied source file to the
   documented textual output (see the LANGUAGE contract in `src/ccomp.c`): first
   the header line `; wordsize <N>`, then one `put` result per `put E;`
   statement, in order.
5. **Self-check passes:** `./build/c0 probe/sample.c /tmp/probe.actual` diffs
   clean against `probe/sample.out`.

## Hidden grading
The harness will copy its own hidden source file to a fresh path and run
`/app/compcert-src/build/c0` over it, then independently recompute the expected
output text (its own calculation, using the documented language + header wordsize
64) and compare **byte-for-byte**. It also verifies that
`build/cert.checked` and `build/oextract.checked` exist. All three checks count.

## Notes
- Your edit boundary is the single self-contained C file `src/ccomp.c`; keep the
  documented language and output contract exact.
- If a stage fails, read the failure output before changing anything. Pay
  attention to what `configure` reports about missing binaries, and to the ABI
  wordsize it decides on.
- There is no randomness; deterministic inputs produce deterministic outputs.
- If the finished backend does not match `probe/sample.out`, treat that as a
  signal that the deployment header or the backend semantics is wrong.