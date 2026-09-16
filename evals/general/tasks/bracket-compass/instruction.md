# Required blocks must reject statement content cleanly

## Situation

`/app/src` is a shallow, pinned clone of the Jinja2 templating project
(`https://github.com/pallets/jinja`), checked out at upstream commit
`37f5b058ee4aaa01994ae4d378fc015bde484933`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
Python source. Python 3.12 and pytest 7.4.3 are installed, together with the
project's own test configuration. There is **no network** at trial time:
everything you need is already in the image; `pip` and `git fetch` will not
work.

## The bug

Jinja2 lets a template author mark a block as *required*:

```
{% block body required %}...{% endblock %}
```

A required block is meant to hold documentation/placeholder content only: the
project's own documentation says a required block "can only contain comments
or whitespace". When a template actually places a *statement* inside a
required block -- a nested child block, a conditional, or any other tag that
produces logic rather than text -- the template is supposed to fail to compile
with a clear template-syntax error, whose message is:

```
Required blocks can only contain comments or whitespace
```

Instead, the parser in this checkout crashes with an internal `AttributeError`
of the form:

```
AttributeError: 'If' object has no attribute 'nodes'
```

and dumps a Python traceback in place of the intended message. Required blocks
containing only whitespace or comments compile fine, and required blocks
containing literal text already produce the intended clear error; the crash is
specific to content made of statements.

## Reproducing the failure

```
python3 /app/probe_required_block.py
```

prints what the parser does with several required-block bodies. For the
statement bodies it prints an `AttributeError` where it should print the
intended template-syntax error.

One-liners that show the same thing:

```
python3 -c "from jinja2 import Environment; Environment().from_string('{% block x required %}{% block y %}{% endblock %}{% endblock %}')"
python3 -c "from jinja2 import Environment; Environment().from_string('{% block x required %}{% if true %}{% endif %}{% endblock %}')"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that a required block
containing statement content always fails to compile with

```
TemplateSyntaxError: Required blocks can only contain comments or whitespace
```

instead of crashing with an internal `AttributeError`, while required blocks
that are empty or contain only whitespace and/or comments keep compiling
exactly as they do today, and ordinary non-required blocks are completely
unaffected.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_inheritance.py -q -p no:cacheprovider
```

The existing inheritance test file is green at the pinned commit; keep it
that way. Add your own tests if that helps you verify (for example required
blocks around loops, assignments, or expressions), but put anything you add
outside the tracked tree (e.g. under /tmp): the verifier requires the working
tree inside the clone to contain exactly one change, so the verdict on your
fix is made by the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that only the minimal tracked source is modified, and that no
  upstream fix was fetched into the clone.

## What the verifier checks

1. The tree is still at commit `37f5b058ee4aaa01994ae4d378fc015bde484933`,
   only the minimal tracked source file is modified, and the upstream fix
   commit was not pulled into the clone.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing inheritance tests still pass.
4. Hidden cases over inputs the upstream test does not use pass, including
   other statement kinds inside required blocks, the exact error contract
   (message text, error class, parse-time behaviour), and the guarantee that
   non-required blocks containing statements still compile.

Deliverable: the repaired `/app/src` tree.