# HTTPX provenance receipt

- Repository: https://github.com/encode/httpx
- License: BSD-3-Clause, confirmed by the repository `LICENSE.md` at the pinned base.
- Upstream reference: https://github.com/encode/httpx/pull/3364
- Base commit: `6f9b50990dad9645a6f9dc0e1eb90af0a6474c3b` (`typo: Reading a response expose response text, not request text (#3359)`)
- Fix commit: `bf5758388619afdc957722ca8a9a4ff255df6866` (`Keep it neat`), the merged PR commit containing the one-file request-construction change.
- Scope verified from the immutable diff: `httpx/_models.py` only; explicit `params` is constructed as a new URL query while `params is None` retains the parsed URL query.

The task image downloads only the base commit. The fix commit, PR discussion, patch, and upstream tests are not copied into the image.
