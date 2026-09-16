# PR/issue to task

Find a real issue or pull request through repository maintenance history. Record
the original reference, source license, affected base commit, reproduction, and
fix commit when available. An issue without a merged fix is eligible only when
the author can build a correct independent reference solution.

Reproduce the reported behavior on the pinned base. Prove the same reproduction
passes after the reference repair. Separate desired behavior from incidental
details of the upstream patch; allow alternative correct implementations.
Translate the report into a self-contained user request. Do not expose the fix
URL, patch, answer-bearing discussion, or fix history in the agent environment.

Add hidden boundary cases and regression checks beyond any upstream test. Check
that an incomplete repair fails. Record unrelated baseline failures so they do not
accidentally determine reward. Reject unverified reports, ambiguous expectations,
and changes whose result cannot be tested offline within the resource budget.

Normalize with `author_task.py pr-issue`, implement the common package, and hand
off to the [shared QA backend](../qa/README.md).
