# FuncParamType must not swallow the validation message

## Situation

`/app/src` is a shallow, pinned clone of the click project
(`https://github.com/pallets/click`), checked out at upstream commit
`5b9630f50fde938b72ad8c99542efe3a6f5717e2`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
Python source. Python 3.12, pip and pytest are installed. There is **no
network** at trial time: everything you need is already in the image; `pip` and
`git fetch` will not work.

## The bug

`click.types.FuncParamType` wraps a user-supplied conversion function (`func`).
When that function raises `ValueError` to reject an input value, click's job is
to turn the rejection into a `click.BadParameter` error whose message explains
to the user why the value was rejected. In this checkout it does not: the
`ValueError`'s own message is thrown away, and the user is shown only the raw
input value echoed back at them.

For example, a conversion function such as

```python
def parse_ip(value):
    raise ValueError("not a valid IP address: expected four octets")
```

produces a `BadParameter` error whose message is just the input value that was
passed in, instead of `not a valid IP address: expected four octets`. Any
validation built on `FuncParamType` -- format checks, port ranges, required
fields -- loses its explanation entirely.

The intended behaviour: the `BadParameter` message must be the `ValueError`'s
message. Only when the exception's message is empty should the raw input value
be shown instead (converted to text robustly, surviving non-decodable bytes).

## Reproducing the failure

Run the probe script:

```
python3 /app/probe_func_param_type.py
```

It prints the message of the `BadParameter` raised by two conversion functions:
one that raises `ValueError("bad value: nope")` and one that raises
`ValueError()` with no message, both fed with the input value `"nope"`.

Today you see the message echoed twice with the real message lost. The output
you should be aiming for (after the fix, and what the verifier expects) is:

```
value 'nope' + ValueError("bad value: nope") -> BadParameter message: 'bad value: nope'
value 'nope' + ValueError() (empty message) -> BadParameter message: 'nope'
```

A one-liner that shows the same buggy path:

```
python3 -c "
import click
def parse(v): raise ValueError('bad value: nope')
t = click.types.FuncParamType(parse)
try: t.convert('nope', None, None)
except click.BadParameter as e: print(repr(e.message))
"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that when a
`FuncParamType` conversion function raises `ValueError` with its own message,
that message is what the user sees in the resulting `BadParameter` error, and
the raw input value is used only when the `ValueError` message is empty. Change
nothing else, and keep the project's existing behaviour for inputs that
convert fine.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_types.py -q -p no:cacheprovider
```

The whole existing test file is green at the pinned commit; keep it that way.
Add your own scratch tests if that helps you verify (for example a conversion
function raising `ValueError` with a multi-word message, or a message raised
for a non-string input value), but remove them again before you finish — the
verifier requires the clone to contain exactly one modified file.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch
  them.
- The verifier also asserts that the working tree remains at the pinned commit,
  that no other tracked files were modified, and that no new files were added
  inside the click package.

## What the verifier checks

1. The tree is still at commit `5b9630f50fde938b72ad8c99542efe3a6f5717e2`, no
   extra tracked files were changed, and the repair touches only the minimal
   source surface.
2. The fix is genuinely present in the tree source: the verifier imports click
   straight from `/app/src` with site hooks disabled and exercises the
   `ValueError` path itself. Patching the installed copy or installing a
   wrapper that intercepts imports does not satisfy this.
3. The project's upstream regression test for this behaviour passes.
4. The project's own existing test suite still passes.
5. Hidden cases over inputs the upstream test does not use pass: a full CLI
   invocation where the `ValueError` message must reach the user's output while
   the raw input must not be echoed, a non-string input value, and a
   `ValueError` whose message must be preserved exactly.

Deliverable: the repaired `/app/src` tree.