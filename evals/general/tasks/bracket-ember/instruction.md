# Exceptions raised for invalid JSON must survive a pickle round-trip

## Situation

`/app/src` is a shallow, pinned clone of the requests library
(`https://github.com/psf/requests`), checked out at upstream commit
`96b22fa18c00831656ee4b286bf1c9062459b00a`, and installed from that tree in
editable (development) mode, so the code you import is exactly the
checked-out Python source. Python 3.12, pytest, urllib3, certifi,
charset_normalizer, idna and PySocks are installed. There is **no network**
at trial time: everything you need is already in the image; `pip` and
`git fetch` will not work.

## The bug

When code fails to decode the text of a response as JSON, requests raises
`requests.exceptions.JSONDecodeError` (for example `Response.json()`
re-raises the stdlib `json.JSONDecodeError` as this wrapper). Any program
that pickles one of these exception objects and unpickles it -- which is
exactly what a `multiprocessing` process pool does when a worker fails on
malformed JSON and the result is re-raised in the parent process -- crashes
on the unpickle step:

```
>>> import pickle
>>> from requests.exceptions import JSONDecodeError
>>> e = JSONDecodeError('Extra data', '{"responseCode":["706"]}{"responseCode":["706"]}', 36)
>>> pickle.loads(pickle.dumps(e))
Traceback (most recent call last):
  ...
TypeError: JSONDecodeError.__init__() missing 2 required positional arguments: 'doc' and 'pos'
```

The exception can be serialized, but reconstructing it drops two of its
three constructor arguments (`doc` and `pos`), so round-tripping it fails
with a `TypeError`; on code paths where reconstruction apparently succeeds,
the reconstructed object does not even have the same repr as the original.

## Reproducing the failure

```
python3 /app/probe_json_pickle.py
```

prints the repr of the original exception and what a pickle round-trip
produces (or the `TypeError` raised by the round-trip). A one-liner that
shows the same thing:

```
python3 -c "import pickle; from requests.exceptions import JSONDecodeError; e = JSONDecodeError('Extra data', '{\"responseCode\":[\"706\"]}{\"responseCode\":[\"706\"]}', 36); print(repr(pickle.loads(pickle.dumps(e))))"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that any
`requests.exceptions.JSONDecodeError` can be serialized with `pickle` and
deserialized again, with the reconstructed object carrying the same
`msg`, `doc` and `pos` values and the same repr as the original, exactly as
the stdlib `json.JSONDecodeError` round-trips.

Consider what the class hierarchy implies: this exception inherits from the
IOError family *and* from the stdlib `json.JSONDecodeError`, and pickle
picks its reconstruction strategy from that hierarchy. The right fix is
small and localized; if it is not, you are likely fixing the wrong thing.

Drive your work from `/app/src` with the project's own test runner:

```
cd /app/src && python3 -m pytest tests/test_utils.py tests/test_structures.py tests/test_lowlevel.py -q -p no:cacheprovider
```

The existing self-contained test files (`tests/test_utils.py`,
`tests/test_structures.py`, `tests/test_hooks.py`, `tests/test_help.py`,
`tests/test_packages.py`, `tests/test_lowlevel.py`) are green at the pinned
commit; keep them that way. Note that some upstream tests need an `httpbin`
endpoint that cannot run here, so do not try to run the whole suite; run the
files above and your own focused checks. Add your own tests if that helps you
verify (for example other `(msg, doc, pos)` payloads, other pickle protocols,
a full `Response.json()` path with an invalid body, or a round-trip executed
in a separate process), but the verdict on your fix is made by the verifier,
which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree remains at the pinned
  commit, that no other tracked files were modified, and that no new files
  were added inside the requests package.

## What the verifier checks

1. The tree is still at commit `96b22fa18c00831656ee4b286bf1c9062459b00a`, no
   extra tracked files were changed, and the repair touches only the minimal
   source surface.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing self-contained test files still pass.
4. Hidden cases over inputs the upstream test does not use pass, including
   pickle round-trips across many `(msg, doc, pos)` payloads and pickle
   protocols, the full `Response.json()` path on an invalid response body,
   and a cross-process round-trip where pickle bytes are written in one
   process and loaded in another.

Deliverable: the repaired `/app/src` tree.