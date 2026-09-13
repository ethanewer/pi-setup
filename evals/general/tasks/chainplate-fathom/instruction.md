# GitLab CI job tokens leak into the project URL Semgrep reports

## Situation

`/app/src` is a shallow, pinned clone of the Semgrep repository
(`https://github.com/semgrep/semgrep`) at upstream commit
`a8b650dffe910d7b8903fe05ceeb75fdc7983197`, checked out in detached HEAD.
The `cli/src/semgrep/semgrep_interfaces` submodule is checked out, and the
Python CLI has been installed in **editable** mode: anything you change
under `/app/src` is live immediately, with no build step and no reinstall.
`pytest` is installed. There is **no network** at trial time: `git fetch`,
`curl` and any other network use will fail.

Driving the work is trivial. The reproduction is a throwaway local git repo
whose remote URL carries credentials (nothing is ever contacted — `git`
only reads its own config):

```
mkdir -p /tmp/pub && cd /tmp/pub && git init -q
git remote add origin https://gitlab-ci-token:glcbt-64_wFuiRFQk9t841JHKQnAT@gitlab.company.world/app/test-case.git
python3 -c "from semgrep.git import get_project_url; print(get_project_url())"
```

## The bug

Semgrep's `get_project_url()` reads the URL of the current git project's
default remote and returns it to callers verbatim. Among other things
Semgrep records where rules and findings came from when publishing rules, so
the returned string ends up inside the rule metadata that gets published.

GitLab CI/CD jobs never run anonymously: every job has a token, and the
remote URL GitLab injects into the build carries that token as HTTP
basic-auth credentials:

```
https://gitlab-ci-token:glcbt-64_wFuiRFQk9t841JHKQnAT@gitlab.company.world/app/test-case.git
```

With the snippet above, that whole URL — including the `glcbt-` job token —
is exactly what `get_project_url()` returns. The token thereby propagates
into published rule metadata and can end up in public artifacts. Only
`https://gitlab.company.world/app/test-case.git` should ever be reported:
the credentials must be stripped, keeping host (and port, if any) and path.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. `get_project_url()` never returns a URL that still contains embedded
   credentials. For the reproduction above it must return exactly
   `https://gitlab.company.world/app/test-case.git`.
2. The project's own regression test for this behaviour — kept out of the
   tree, at `/opt/golden/test_clean_project_url.py` — imports a module-level
   function `clean_project_url` from the module that implements project-URL
   handling in this codebase, and asserts that the very URL above rewrites
   to the bare URL. Your fix must provide that function, with that name and
   that behaviour, so the regression test passes against your repaired
   tree.
3. URLs that carry no credentials are returned unchanged: a plain
   `https://host.example.org/org/repo.git` must come back byte-for-byte as
   it was. And the project's existing unit test
   `tests/unit/test_baseline.py` (which drives the same module's
   `BaselineHandler`, `git_check_output` and working-tree machinery) must
   still pass.

The fix is small, but you are expected to find it in this tree and implement
it there, not to work around it elsewhere: the verifier checks working-tree
provenance (below). Work from the reproduction; iterate with one-liners
like the one in the snippet until `get_project_url()` returns the bare URL,
then run the project's tests the way the verifier will (from
`/app/src/cli`):

```
cd /app/src/cli && python3 -m pytest -q tests/unit/test_baseline.py
```

## Constraints

- Network is unavailable; everything needed is installed and offline.
- The clone at `/app/src` is the deliverable. Change it in place and
  minimally: do not rewrite history, add remotes, fetch, commit, add or
  rename files inside the repository, or change build files. After your
  edit the **tracked** working tree must differ from the pinned commit
  only in the module that implements project-URL handling, and that module
  must actually have been changed.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. Provenance: `/app/src` is still pinned to the parent commit, the object
   store still holds exactly that one commit (so nothing was fetched),
   the working tree differs from the pinned commit only in the module that
   implements project-URL handling, that module was changed, and the
   installed `semgrep` package resolves to `/app/src`.
2. The project's own regression test passes: `clean_project_url` exists
   with the name above and strips the GitLab CI job token from the reported
   project URL.
3. The project's existing unit test `tests/unit/test_baseline.py` passes.
4. Hidden cases: more credential-bearing URLs — different hosts, ports and
   token styles, exercised both through `get_project_url()` end to end in
   real throwaway git repos and through `clean_project_url()` directly —
   all come back credential-free, while URL forms that carry no
   credentials, and SSH/scp-style forms that are not HTTP basic-auth, are
   left untouched.

Deliverable: the repaired `/app/src` tree.