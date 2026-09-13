# Template variables silently refuse to expand to falsy config values

## Situation

`/app/src` is a shallow, pinned clone of the poetry repository
(`https://github.com/python-poetry/poetry`) at upstream commit
`e54180064368c2f9d9ad5ff4771d8b33538cc372`, checked out in detached HEAD.
The clone deliberately carries no git remotes, and there is **no network**
at trial time: `git fetch`, `curl` and any other network use will fail.

The project is installed in editable mode into the virtualenv at
`/opt/poetry-venv`, so the code you import or test is exactly the checked-out
tree, and an edit takes effect immediately. The whole `tests/config`
directory of the project's own test suite runs offline in under a second:

```
cd /app/src
/opt/poetry-venv/bin/pytest tests/config/ -p no:randomly -o addopts="" -q
```

## The bug

Poetry's configuration system lets one config value embed another through a
template of the form `{dotted.config.key}` inside a string value. When a
string value is resolved, each embedded template is looked up in the config
and replaced with the referenced value's string form.

In this checkout, template replacement breaks for **falsy** referenced
values. When the referenced config key holds `0`, `False`, or an empty
string, the value is treated as if the key were unset, and the placeholder is
left literally unexpanded — the resolved value contains the raw text
`{dotted.config.key}` where a concrete value should appear. Users who
legitimately configure `requests.max-retries = 0` (the shipped default retry
count is exactly `0`) or a false boolean see the template text in place of
the configured value.

The tree's own test suite already contains the regression case for this
behaviour. Run just that case:

```
cd /app/src
/opt/poetry-venv/bin/pytest tests/config/test_config.py \
    -k test_config_process_resolves_falsy_values \
    --no-header -p no:randomly -o addopts=""
```

You will see it fail:

```
tests/config/test_config.py:61: AssertionError: assert '{requests.max-retries}' == '0'
1 failed, 82 deselected
```

That is the bug: the referenced value `requests.max-retries` is the integer
`0`, so the literal template string is returned instead of its resolved form.

You can poke the behaviour directly:

```
/opt/poetry-venv/bin/python - <<'PY'
from poetry.config.config import Config
c = Config()
print(repr(c.process("{requests.max-retries}")))   # buggy: '{requests.max-retries}'
print(repr(c.process("{cache-dir}")))              # truthy string value, resolves to the path
PY
```

## What you need to do

Repair the checked-out tree at `/app/src` so that template resolution treats
a referenced value as present whenever the key is configured, including when
its value is falsy (`0`, `False`, `""`), and substitutes the value's string
form. After your fix:

1. The regression case `test_config_process_resolves_falsy_values` passes.
2. The entire `tests/config` directory of the project's own suite passes
   (≥ 100 tests), so nothing else is broken and truthy resolution, missing-key
   handling, environment-variable configuration and everything else behave
   exactly as before.

Drive your work with the project's own test runner from `/app/src`, as above.
Add your own scratch checks anywhere you like while debugging, but keep
experiments out of the tracked tree (for example under `/tmp`): the verifier
requires the working tree inside the clone to end up differing from the
pinned commit in exactly two files — the regression-test file the image
already carries, and the minimal source change that fixes the bug.

## Constraints

- No network. Everything needed is already installed; nothing needs to be
  downloaded.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, do not re-add remotes, do not fetch,
  do not change build or test files, and do not add files anywhere inside the
  repository. The regression test in `tests/config/test_config.py` is part of
  the image as the fix intended it and must stay byte-identical to the golden
  copy at `/opt/golden/`; treat the tests as the spec.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. Tree provenance: still at the pinned commit, no fix was fetched into the
   clone (there are no remotes to fetch from, and the upstream fix commit is
   not present as an object), the working tree differs from the pinned commit
   in exactly the two files above, and `tests/config/test_config.py` is
   byte-identical to `/opt/golden/test_config.py`.
2. The project's own regression case for this bug passes when run from the
   repaired tree.
3. The project's own existing `tests/config` suite passes fully.
4. Two hidden cases drive the same code path from inputs the regression test
   does not use: falsy booleans and a zero from the configuration
   dictionary / the `POETRY_*` environment route, and empty-string values.

Deliverable: the repaired `/app/src` tree.