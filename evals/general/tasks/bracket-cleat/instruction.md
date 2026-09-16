# bracket-cleat: an optional-value flag that click refuses to accept

## Situation

`/app/src` is a shallow, pinned clone of the click project
(`https://github.com/pallets/click`), checked out at a specific upstream
commit, and installed from that tree in editable (development) mode, so the
code you import is exactly the checked-out Python source. Python 3.12 and
pytest are installed. Do not rely on the network: nothing in this task
requires it, fetching or installing is prohibited below, and the verifier
actively rejects trees that pulled in upstream objects.

Click is the well-known Python CLI framework. Options are declared with
`@click.option(...)`. An option can be declared as a *flag* that always
carries a fixed value (`is_flag=True` with `flag_value=...`). It can also be
declared `is_flag=False` while still supplying a `flag_value` and a
`default`; this mixed form is meant to behave like a flag whose value may
optionally be overridden explicitly on the command line.

## The bug

In this checkout, one reasonable declaration fails at runtime:

```python
import click

@click.command()
@click.option("--name", is_flag=False, flag_value="Flag", default="Default")
def hello(name):
    click.echo(f"Hello, {name}!")
```

Invoking the command with the option name and **no value** fails instead of
running:

```
$ hello --name
Error: Option '--name' requires an argument.
(exit code 2)
```

The option should be usable valueless: passing `--name` by itself should use
the `flag_value` ("Flag") and succeed, exactly as an ordinary flag would,
while an explicit value (`--name Bob` or `--name=Bob`) should still be
accepted when one is supplied, and the `default` should still be used when
the option is absent entirely.

## Reproducing the failure

```
python3 /app/probe_flag_value.py
```

This prints the exit code and captured output for invoking the command above
with `--name` and no value. On this checkout it reports `exit: 2` together
with the "requires an argument" error.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that an option declared
with `is_flag=False` together with an explicit `flag_value` and a `default`
behaves like a valueless flag. The behaviour contract your fix must satisfy:

- `--name` (no value) → the option takes its `flag_value` ("Flag"), exit
  code 0, output `Hello, Flag!`.
- `--name Bob` and `--name=Bob` → the option takes the explicit value
  "Bob", exit code 0, output `Hello, Bob!`.
- Option absent entirely → the option value is the `default` ("Default"),
  exit code 0, output `Hello, Default!`.
- A following token that starts with `-` (for example another option) is
  **not** swallowed as the value: `--name --other` sets `name` to the flag
  value and still parses `--other`.
- Options that do *not* set a `flag_value` keep their current behaviour,
  and ordinary `is_flag=True` flags keep theirs. Do not change how explicit
  values are consumed for the options that already require them.

Drive your work with the project's own test runner from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_options.py tests/test_arguments.py tests/test_basic.py -q -p no:cacheprovider
```

These suites are green at the pinned commit; keep them that way. Add your
own tests if that helps you verify (for example short-option variants such
as `-n`, type-converted `flag_value`s, or `multiple=True` options mixing
bare and explicit values), but the verdict on your fix is made by the
verifier, which also checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or install other packages.
  Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them.
- The verifier also asserts that the working tree remains at the pinned
  commit, that no tracked files outside the minimal repair surface were
  modified, and that no new files were added inside the library package.

## What the verifier checks

1. The tree is still at the pinned commit, no extra tracked files were
   changed, the repair touches only the minimal source surface, and the
   upstream fix was not fetched by the agent.
2. The project's upstream regression test for this behaviour (extracted at
   image-build time from the upstream fix into `/opt/golden`) passes.
3. The project's own existing option, argument and basic parsing tests still
   pass.
4. Hidden cases over inputs the upstream test does not use pass: short-option
   and attached-value forms, type-converted flag values, `multiple=True`
   mixing bare and explicit values, and a valueless flag appearing among
   positional arguments.

Deliverable: the repaired `/app/src` tree.