# Baseline receipt

The baseline was evaluated from a clean archive of commit
`5ef70112a1ff19c05324ff889dd30405b1002044`, with no task patch applied.

Pinned local test dependencies: Python 3.12, `MarkupSafe==3.0.2`,
`pytest==8.3.5`, and `trio==0.29.0`.

Behavioral reproduction:

```text
PYTHONPATH=<clean-source>/src python -m pytest -q tasks/repo-216a52efac63/tests/test.py tasks/repo-216a52efac63/tests/hidden
result: exit 1; 5 failed, 4 passed
```

The failures include `map(attribute="name", default=None)` returning
`[Undefined]` and `groupby("name", default=None)` raising an undefined-value
error. This is the intentional baseline gap.

Regression baseline:

```text
PYTHONPATH=<clean-source>/src python -m pytest -q <clean-source>/tests --disable-warnings
result untouched baseline: 911 passed, exit 0

PYTHONPATH=upstream/src python -m pytest -q upstream/tests
result after oracle patch: 911 passed, exit 0
```

The host's default Python 3.9 interpreter was not used because the source
requires Python 3.10+; all recorded runnable results use Python 3.12.
