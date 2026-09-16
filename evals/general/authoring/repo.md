# Repo to task

Choose a production repository for a practical engineering workflow: implement a
bounded feature, repair an integration, improve an algorithm, migrate an API, or
diagnose a configuration problem. Inspect its documentation, architecture,
dependencies, and tests at a full immutable base commit. Record license and source
receipts. Repository selection follows workflow value and suite diversity.

Build and run the baseline before authoring the task. Define a new objective with
observable acceptance criteria. Keep the scope feasible for the assigned compute
and time budget. Author an independent solution and tests, including regressions
for existing behavior and plausible incomplete implementations.

Fetch pinned source and dependencies at image build time; run evaluation offline.
Keep only the necessary source snapshot and remove solution artifacts, remotes,
and history that disclose the answer. Document baseline failures explicitly.
Reject candidates with unreproducible builds, unclear licensing, or no meaningful
distinction between the starting state and a successful solution.

Normalize with `author_task.py repo`, implement the common package, and hand off
to the [shared QA backend](../qa/README.md).
