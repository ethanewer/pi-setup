# Scp-like git remotes are not turned into https links

## Situation

`/app/src` is a shallow, pinned clone of semgrep (`https://github.com/semgrep/semgrep`),
the open-source static analysis tool, checked out at upstream commit
`bb89271f8418167b9d4cee2668e3d38a36003978` and installed from that tree in
editable (development) mode (`pip install -e ./cli`), so the code you import is
exactly the checked-out source. Python 3.12, `pytest`, and the packages the
project's own `cli/setup.py` resolves are installed; the
`cli/src/semgrep/semgrep_interfaces` submodule is already initialised. There is
**no network** at trial time: everything you need is already in the image; `pip`
and `git fetch` will not work.

## The bug

Semgrep converts a repository's git remote into an https URL before linking
findings in a report. For most remotes this works, but a remote written in the
**scp-like shorthand** — `user@host:owner/repo`, with no protocol prefix such as
`ssh://` or `https://` and no trailing `.git` — is left alone: the URL that gets
recorded keeps the raw scp form, so the links shown for the report are broken.

The failure appears specifically when the organisation or repository name
contains a **dash**. For example:

```
git@code1.somecompany.internal:somecompany-eval/owasp-juice-shop
```

`get_url_from_sstp_url` (the function that produces the link for each supported
CI provider) accepts the URL above, but instead of returning

```
https://code1.somecompany.internal/somecompany-eval/owasp-juice-shop
```

it returns the input unchanged. Remotes that spell out a protocol
(`ssh://...`, `https://...`) or end in `.git` parse correctly.

## Reproducing the failure

```
python3 /app/probe_git_url.py
```

runs semgrep's URL conversion on several remotes and compares each result with
the correct https form. While the bug is present it prints the mismatches
(including the input-unchanged case above) and exits with status 1.

You can also drive the failing path directly, from `/app/src/cli`:

```
cd /app/src/cli && python3 -c "from semgrep.meta import get_url_from_sstp_url; print(get_url_from_sstp_url('git@code1.somecompany.internal:somecompany-eval/owasp-juice-shop'))"
```

## What you need to do

Find the root cause in the real tree and fix it so that dash-containing
scp-like remotes are converted to their https form, without changing the output
for any of the URL shapes that already work (explicit protocols, trailing
`.git`, http(s) remotes, tilde forms).

Drive your work with the project's own test runner, from `/app/src/cli` (the
project's pytest configuration lives in `cli/pyproject.toml`):

```
cd /app/src/cli && python3 -m pytest -q -p no:cacheprovider -o addopts=""
```

The targeted unit tests that exercise this area and do not need the
`semgrep-core` binary are `cli/tests/default/unit/test_clean_project_url.py`
and `cli/tests/default/e2e-pro/test_meta.py`; both pass at the pinned commit.
Tests that invoke the semgrep CLI itself need the core binary, which is not
built in this image, so stick to the pure-Python tests. Add your own tests if
that helps you verify (for example more scp-like shapes, or a guard that
explicit-protocol URLs are unaffected), but the verdict on your fix is made by
the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that no history was fetched or added, that no tracked files were
  deleted, that the only modified tracked files are source files under
  `cli/src/semgrep/` (at least one such modification is present), and that
  `import semgrep` still resolves to the checked-out tree at `/app/src` (it
  does; do not reinstall or move anything).

## What the verifier checks

1. The tree is still at commit `bb89271f8418167b9d4cee2668e3d38a36003978`,
   the working clone contains no other history (nothing was fetched or
   added), no tracked file was deleted, only source files under
   `cli/src/semgrep/` are modified (at least one), and `import semgrep`
   resolves to `/app/src/cli/src/semgrep`.
2. The project's own upstream regression test for this behaviour passes
   (that test is kept out of the tree at `/opt/golden/` and copied in by the
   verifier).
3. The project's own existing tests for this area still pass.
4. Hidden cases over scp-like and protocol URL shapes the regression test
   does not use pass.

Deliverable: the repaired `/app/src` tree.