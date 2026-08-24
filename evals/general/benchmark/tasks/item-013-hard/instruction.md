# Hardened staged "certified C" toolchain build (c0)

In `/app/cc-src` is a **source snapshot** of a CompCert-3.13.1-style staged
"certified C" front-end build called **c0**. It is shipped **unbuilt and
defective**: the toolchain is incomplete, the backend source does not compile
as shipped, and a stale build artifact is lying in wait. Your job is to bring
the build up through its stages, find and clear every planted defect, and reach
a correct `build/c0` with all staged sub-artifacts present.

Read `/app/cc-src/README.md` first — it enumerates the planted problems, the
exact stage order, the toolchain you must install, the authoritative-header
constraint, and the self-check.

## Hard requirements (all must hold at the end)

1. **Toolchain up.** `gcc`, `ocamlc`, and `coqc` are all available on the host.
   `./configure` probes for them and refuses to proceed if any is missing. On
   Ubuntu install the missing Debian packages (e.g. `apt-get install -y ocaml coq`).
2. **Compiles under the strict backend flags.** The `backend` stage builds with
   `gcc -Wall -Werror -O1 -Ibuild -o build/c0 src/ccomp.c`. The shipped source
   fails this; read the compiler log, remove the benign offending line, change
   nothing else about the language contract.
3. **Authoritative header.** `build/machine.h` shipped with the tree is stale
   (`C0_WORDSIZE 32`) and is **not** authoritative. `./configure` regenerates a
   correct `build/machine.h` from the host ABI — the intended **wordsize is 64**.
   Only the regenerated header may exist / be compiled in.
4. **Certified stages:** `build/cert.checked` (Coq `verify`) and
   `build/oextract.checked` (OCaml `oextract`) both exist, produced genuinely by
   those stages, not synthesized.
5. **Backend behavior:** `build/c0 <in> <out>` writes the documented output:
   first line `; wordsize 64`, then one value line per `put E;`, in order. The
   language grammar and value semantics are documented at the top of
   `src/ccomp.c`.
6. **Self-check passes:** `./build/c0 probe/sample.c /tmp/probe.actual` diffs
   cleanly against `probe/sample.out`.

## Hidden grading

The harness copies its own hidden source program to a fresh path and runs
`/app/cc-src/build/c0` over it, then independently recomputes the expected output
(its own calculation with the documented grammar and header wordsize 64) and
compares byte-for-byte. It also checks that the two certified staged artifacts
exist. All checks count; nothing else is inspected.

## Notes
- The planted "hint" comment in `src/ccomp.c` does not describe the correct
  fix; trust the compiler diagnostic instead.
- If `probe/sample.out` does not match your backend's output on the sample,
  double-check (a) the wordsize in the regenerated header and (b) the backend
  grammar before touching anything else.
- The grading is deterministic; inputs are guaranteed valid for the documented
  grammar.