# v4.3 verified upstream issue pool

One JSON file per upstream repository, written by the mining phase of the v4.3
wave. Each entry is a REAL upstream bug fix, mined from the project's own git
history and then empirically verified in both directions before it was allowed to
become a task:

- the fix commit references a real issue or pull-request number;
- it changes at least one source file and at least one test file;
- at the parent commit, with the fix commit's own test file checked out, the
  reproduction FAILS;
- at the fix commit, the same reproduction PASSES.

That last pair is what makes the issue real rather than merely mentioned. Mining a
commit whose message says "fix #123" is not evidence: the first prototype of this
method appeared to verify httpx #3412 as non-reproducing, and the cause was that
`git checkout <sha> -- <path>` stages the file, so a later `git checkout .`
restored the staged fix instead of the parent. Every verification here must use
`git reset --hard <sha>` and confirm the buggy code is actually present before
concluding anything.

Entries record the parent and fix commits as full 40-hex SHAs, the test paths to
extract from the fix commit, the exact reproduction command, the dependency
versions the reproduction needs, and a paraphrase of the issue in the author's own
words. Tasks built from an entry clone the repository at the parent commit and
extract the golden test from the fix commit at image-build time with
`git show <fix>:<path>`, so upstream bytes never enter this repository.

The upstream issue number is deliberately NOT to be quoted in a task's
instruction.md. Trials have network egress (see reports/v42_wave.md section 9), so
naming the issue would let an agent look up the fix instead of finding it.
