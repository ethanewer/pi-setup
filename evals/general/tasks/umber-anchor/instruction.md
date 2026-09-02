# Umber Anchor — reproducible dev environment

You are bringing up a reproducible development environment inside one Linux
image. Python 3.12, `pip`, and `zsh` are available, and a small **zsh
framework** (`zframe`) is already installed under `/app/zframe`. Everything you
touch lives under `/app`. Do not modify anything outside `/app`.

You must produce **four deliverables**, all under `/app`:

| path | what it must be |
|---|---|
| `/app/requirements.txt` | dependency manifest you author |
| `/app/environment.lock` | environment spec you FIX (it currently has a conflict) |
| `/app/.zshrc` | your user rc wiring the zsh framework |
| `/app/confirm_versions.py` | a generalized version-constraint checker |

The verifier executes all four for real afterwards, so each must be a genuine,
runnable artifact — no hard-coded one-offs.

---

## 1. Author the dependency manifest — `/app/requirements.txt`

Create a pip-requirements-style manifest that declares the scientific dev
dependency set. It **must** list, with pinned-version operators (`==`, `>=`,
`<=`, or a compatible range — never an unpinned bare name for these):

- `numpy` (base array/numeric library)
- `pandas`
- at least one **plotting / scipy-family** library — `scipy` and/or
  `matplotlib`

Anything else is optional. The file must be such that **`pip install -r
/app/requirements.txt` succeeds** in this environment (the corporate proxy is
configured for you; if you test, local resolution is the reliable check).

Example of an acceptable manifest:

```
numpy==1.26.4
pandas==2.2.2
scipy==1.13.1
matplotlib==3.9.1
```

## 2. Fix the version conflict — `/app/environment.lock`

`/app/environment.lock` is an existing numeric-solver environment spec in
pip-requirements format. It is **currently broken**: the base numerical library
(`numpy`) is pinned to a version that clashes with the solver library
(`scipy`) it is paired with, so `pip install -r /app/environment.lock` cannot
build one consistent set (`ResolutionImpossible`).

Edit `/app/environment.lock` so the resolver **builds a consistent set** —
i.e. `pip install -r /app/environment.lock` succeeds. Two example directions
that work: re-pin `numpy` down to a version the pinned `scipy` accepts (for
example `numpy==1.26.4` with `scipy==1.12.0`), or raise `scipy` to a release
that accepts the current `numpy`.

## 3. Install and configure a zsh framework — `/app/.zshrc`

The light-weight zsh framework is installed at `/app/zframe`
(`/app/zframe/load.zsh` loader, `themes/`, `plugins/`). Author `/app/.zshrc`
that activates it with a specific **theme** and an exact **plugin set**.

It must:
- set `export ZSH_THEME="midnight"` (the theme `midnight` must be one provided
  under `/app/zframe/themes/`);
- set the `plugins` array exactly to `github history-substring-search
  zsh-autosuggestions` (in that order, by their plugin names);
- `source` the framework loader so the theme and every plugin are actually
  activated.

The loader sets `$THEME_STATUS` to `active:<theme>` and `$PLUGIN_STATUS` to a
comma-joined list of the plugins it actually loaded. The verifier sources
`/app/.zshrc` in a fresh, non-interactive `zsh` and requires exactly
`THEME_STATUS=active:midnight` and
`PLUGIN_STATUS=github,history-substring-search,zsh-autosuggestions` (no `:missing`
entries).

## 4. Version-constraint checker — `/app/confirm_versions.py`

Write `confirm_versions.py` as a general, executable CLI:

```
python3 /app/confirm_versions.py <MANIFEST>
```

It reads `<MANIFEST>` (a pip-requirements-style file) and, for each named
distribution, verifies that the **version currently installed in the
environment that runs the script** satisfies every specifier. Exit `0` only if
every named dist is installed and satisfies all its constraints; otherwise
print one informational line per problem and exit non-zero.

The verifier runs **your exact program** on new hidden manifests, so it must
handle, deterministically and documented behaviors (no hard-coded package
names):

- blank lines and lines starting with `#` are ignored; text after `#` on a line
  is ignored;
- lines starting with `-` (e.g. `-r other.txt`, `--index-url ...`) are **skipped
  without being opened**;
- a line with no version operator is a bare package name — it only needs to be
  installed to pass;
- supported operators: `==`, `===`, `!=`, `>=`, `<=`, `>`, `<`, `~=`, and the
  `==X.Y.*` wildcard; comma-joined combined specs are supported
  (`numpy>=1.24,<2.0`);
- a package that is **not installed** is a failure (`MISSING`);
- an installed version that **violates** a constraint is a failure
  (`MISMATCH`);
- an unparseable specifier is reported as an error (never crash / no traceback).

You may test against the installed environment. Produce the file as
`/app/confirm_versions.py`; leave it runnable with its shebang and `chmod +x`.

---

Keep paths literal under `/app`. Do not modify `/tests` (you cannot see it) or
anything outside `/app`. All four deliverables must exist and be executable /
usable when the verifier runs.