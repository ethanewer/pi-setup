# Help when invoked with no arguments must not look like success

A real upstream checkout of the `click` command-line library is installed at
`/app/src` (an editable install: `import click` loads the code from
`/app/src/src/click`). There is a bug in this checkout. Fix it.

## The symptom

`click` commands and groups can be configured with `no_args_is_help`: when
the user invokes the command with no arguments, the library prints the help
text. That part works. The problem is what the process does afterwards.

Today, invoking such a command with no arguments (and invoking a group with no
subcommand and no arguments) prints the help text and then exits with status
**0** — exactly the status of a successful run. A script that calls the
command cannot tell that nothing actually ran and that only help was shown. In
a command line, showing help in this situation is an error condition (the user
asked for something and did not get it done), and `click`'s convention for
usage errors is exit status **2**. Help shown via `no_args_is_help` must end
the process with exit status **2**, the same as every other usage error
(`UsageError`), so callers can distinguish "help was shown" from "the command
ran".

## Your job

1. **Write a failing reproduction first.** Create a pytest test file at
   `/app/repro/test_no_args_is_help.py`. It must capture the bug above for at
   least the basic `Command` case (and may add a group case), asserting the
   *correct* behaviour: invoking with no arguments shows the help text and
   yields exit status `2`. Confirm it **fails** against the code as it stands
   in `/app/src` right now. This file is a deliverable and will be checked.

2. **Fix the library** so the reproduction passes, with the fix made in the
   click source under `/app/src/src/click` — not by changing your
   reproduction, not by touching the project's test suite, and not by wrapping
   or monkey-patching anything. The `click` package must behave correctly for
   anyone who uses it.

3. **Keep everything else working.** The project's own test suite lives at
   `/app/src/tests` (self-contained, downloads nothing). After your change the
   suite must still pass, and behavior for ordinary invocations must be
   unchanged. In particular, calling a group with no command and no arguments
   today shows its help; after your fix that must still show help, only with a
   non-zero usage-error status.

## Deliverables

- `/app/repro/test_no_args_is_help.py` — your reproduction as pytest tests,
  written first, confirmed failing on the unmodified tree, passing after your
  fix.
- The fixed click library in `/app/src`.

## Environment facts

- No network at trial time. Everything is already in the image: Python 3.12,
  pytest 9.1.1, the editable `click` install. Do not re-clone or reinstall.
- `/app` is writable; the checkout at `/app/src` is writable.
- `CliRunner` from `click.testing` captures exit status and output; you can run
  a single test file with `python3 -m pytest -q <file>`.
- The project's test suite at `/app/src/tests` is your ground truth — write and
  run your reproduction, then fix the library, then make sure the suite still
  passes (the core files `test_basic.py`, `test_options.py` and
  `test_chain.py` are a reasonable check while you iterate).

The interesting part is determining where the exit status actually comes from
in the library, and what the correct repair is. The bug is real upstream code;
fix it properly, the way a maintainer would.