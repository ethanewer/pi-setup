---
name: jinja-extension-workflow
description: Trace and implement a bounded Jinja behavior change across public API, runtime semantics, and regression tests; use for repository-level Jinja maintenance tasks, not template-only authoring.
---

# Jinja extension workflow

Use this workflow when changing Jinja itself. Start from the public entry point
and follow the call chain into the environment, compiler, runtime helper, or
loader that owns the behavior. Check neighboring tests and documentation before
choosing the smallest compatible change.

For a new behavior, define the observable contract first: normal input, empty
or missing input, wrong-but-plausible input, and interaction with configured
environment options. Preserve existing exception types and messages unless the
task explicitly changes them. Prefer an implementation that works for both the
direct public API and the equivalent template expression when both paths exist.

Add regression tests at the narrowest existing test layer, then run the focused
tests and the repository's relevant broader suite. When evaluating a proposed
patch, inspect the diff for accidental changes to undefined handling, autoescape,
async execution, and state shared by reused environments.
