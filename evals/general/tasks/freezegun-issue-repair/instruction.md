# Repair `as_arg` decorator invocation in Freezegun

The directory `/app/freezegun_base` contains a self-contained snapshot of Freezegun at the pinned pre-fix revision, including its Apache-2.0 license. Do not download anything or use network access.

Repair the public API so `freeze_time(..., as_arg=True)` prepends the active time factory and invokes the decorated callable exactly once with the caller's original positional and keyword arguments. `as_kwarg="name"` must continue to inject a factory under that keyword, and requesting both modes must still raise the existing assertion.

Create or maintain these deliverables:

- `/app/freezegun_base/freezegun/api.py` (the library repair; do not replace it with a dependency or wrapper)
- `/app/reproduce.py` (an executable standalone reproduction using only the public Freezegun API)

The reproduction's stdout contract is exact: on success it must contain exactly two newline-terminated lines, `BUILT PASS` followed by `CALLS 2`, with no other stdout. It must exit zero only when an `as_arg=True` decorated function gets the factory first, receives its original positional and keyword-only arguments unchanged, sees the requested frozen date, and is invoked once, and an `as_kwarg="frozen"` function also receives the expected factory and is invoked once. On a failed check it must still print exactly two lines of the form `BUILT FAIL` and `CALLS <observed-count>` and exit nonzero. Keep it deterministic and offline.

The reproduction must honor the optional `FREEZEGUN_SOURCE` environment variable: when it is set, import Freezegun from that directory; otherwise default to `/app/freezegun_base`. Do not hard-code or ignore this override, because the verifier uses it to run the same reproduction against a trusted pristine source fixture.

Preserve normal context-manager freezing, the default decorator behavior, and existing `as_kwarg` behavior. Do not edit or add tests outside the two deliverables. Use plain Python and keep the implementation suitable for one CPU and 4096 MB. The verifier supplies hidden cases including a generator function, keyword arguments, normal context-manager/default decorator behavior, and negative controls against the unrepaired snapshot.
