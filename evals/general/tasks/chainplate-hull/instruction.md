# chainplate-hull

You are working inside a real open-source codebase: **starship**
(`starship/starship`), the cross-shell prompt engine, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's prompt-formatting machinery. Your job is to find it, fix it
in the working tree, and prove the fix with the project's own test tooling.
You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed and on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency — do **not**
  run `cargo update` or change the lockfile.
- **There is no network** in this container. Everything needed is baked in:
  the crates.io dependency cache and a warm `target/` build directory (the
  whole workspace, the `starship` binary and the test harness were compiled
  at image build time at this same commit). Any `cargo` command you run
  completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

Prompt format strings are built from *textgroups* — bracketed sections such
as `[text](style)`. A textgroup may be empty, leaving only a style:

```
[](bg:red)
```

This is exactly how powerline-style prompts set the background color for
*following* segments without printing anything: later segments inherit it
through the special style variables `prev_fg` / `prev_bg`.

In this tree that pattern silently does nothing. An empty textgroup is
discarded entirely, so it never establishes a style for later segments to
inherit, and `prev_fg` / `prev_bg` references have nothing to resolve
against. Concretely, a format with an empty red-background textgroup
followed by a text segment that asks for `bg:prev_bg` renders the text with
**no background at all**.

Reproduce it:

```bash
cd /app/src
cargo build --locked      # debug binary (the image already warmed this build)

printf 'format = "[](bg:red)[X](bg:prev_bg)"\nadd_newline = false\n' > /tmp/fmt.cfg
STARSHIP_CONFIG=/tmp/fmt.cfg ./target/debug/starship prompt | od -An -c
```

On the buggy tree this prints just

```
   X
```

— a single `X` byte and nothing else. The correct rendering is `X` on a red
background: the output bytes must be

```
 033   [   4   1   m   X 033   [   0   m
```

(i.e. `ESC [ 4 1 m X ESC [ 0 m`, background colour 41) — the empty group
first switches on the red background, then `X` is printed on it, then a
reset. There is no crash anywhere; the bug shows up only as missing escape
bytes.

## Requirements

1. Fix the tree so that the reproduction above prints exactly `ESC [ 4 1 m
   X ESC [ 0 m` (checked with `od -An -c`) and exits 0. The same
   format string, run before your fix, prints a bare `X`; after your fix it
   must carry the background through.
2. Fix the mechanism, not just this one input: an empty textgroup must
   establish the style that later segments inherit through `prev_fg` /
   `prev_bg`, no matter the color, the color space used (`red` or a hex
   color like `#9A348E`), the reference (`bg:prev_bg` or `fg:prev_fg`), or
   how many empty groups precede the dependent segment. Do not patch the
   reproduction's inputs, do not special-case the test format string, and
   do not add a style-inheritance workaround outside the formatter — the
   intended behaviour is that the empty group itself carries the style.
3. Everything else must keep working exactly as before: ordinary styled
   textgroups, textgroups with text, nested groups, variables, and shell
   escaping must all be unchanged. The project's existing unit-test suite
   for the formatter must stay green.
4. The graded tree must be byte-identical to the pinned commit except for
   the **single source file where the bug lives** (in `src/formatter/`).
   Locating that file is part of the task: read the prompt formatter so you
   understand how a textgroup becomes output segments and how `prev_fg` /
   `prev_bg` resolve. Do not add, move, delete, rename or reformat any
   file; if you create scratch files to investigate, delete them before you
   finish; make no commits; do not modify `tests/`, `Cargo.toml`,
   `Cargo.lock` or any metadata file. The grader compares every file's
   bytes against the pinned commit's own blobs, so cosmetic side-changes
   also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `cargo build --locked` and the one-liner above
   (scratch config files in `/tmp`, never inside `/app/src`).
2. **Localise** the bug: the formatter lives in `src/formatter/`. Read how
   a textgroup is parsed and turned into `Segment`s, and how the
   `prev_fg`/`prev_bg` style variables are resolved against the *previous*
   segment. Understand why an empty group can currently produce no segment
   at all, and what that implies for the first dependent segment after it.
3. **Fix** with the smallest possible change in that one file, rebuild
   (`cargo build --locked`), and confirm the reproduction prints
   `ESC [ 4 1 m X ESC [ 0 m`. Also try a variant that uses the foreground:
   `format = "[](fg:red)[X](fg:prev_fg)"` must render `X` in red, and a
   variant with a hex color, `[](bg:#9A348E)`, must work the same way.
4. **Prove nothing else broke**: the project's unit tests are inline
   `#[cfg(test)] mod tests` blocks in the source files, run with e.g.
   `cargo test --locked -- test_nested_textgroup test_styled_variable_as_text
   test_style_variable_nested test_meta_variable test_conditional
   test_nested_conditional test_bash_escape test_default_style` — every one
   of these passes on the pristine tree and must still pass after your fix.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that every tracked
  file except the single formatter source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails), and that the upstream fix commit is not
  reachable from the clone;
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression tests** for this bug (three inline
  unit tests baked into the image at `/opt/golden` — upstream added them
  with the fix, so they do not exist in this tree) into the formatter
  source file, rebuild the test harness offline, and run them: all three
  must pass, and the selection of the project's existing formatter unit
  tests listed above must still pass;
- run `target/debug/starship prompt` directly against **hidden CLI cases** —
  other format strings that reach the same code path (different colors, the
  `fg:prev_fg` direction, chained empty groups, and a non-empty group
  followed by `bg:prev_bg`) — and byte-compare each output against the
  expected rendering. One of these cases is generated **inside the verifier**
  with a random hex background color chosen at grading time and an expected
  byte sequence computed from that color by the ANSI escape formula; since
  the input is produced during grading, no precomputed or hardcoded answer
  can anticipate it. This is why requirement 2 insists the fix be general:
  the graded cases are not enumerable in advance.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.