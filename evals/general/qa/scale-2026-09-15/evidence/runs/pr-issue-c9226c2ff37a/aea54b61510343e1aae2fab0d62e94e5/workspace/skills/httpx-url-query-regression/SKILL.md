---
name: httpx-url-query-regression
description: Diagnose and regression-test HTTPX URL construction changes, especially explicit query-parameter replacement and preservation semantics.
---

# HTTPX URL/query regression workflow

Use this skill when repairing or reviewing HTTPX request URL construction, especially a
regression in how the `params` argument interacts with a query already present in the URL.
Keep the scenario offline and validate through public request construction APIs.

- Reproduce through the public `httpx.Request` or client-building API, not private URL internals alone.
- Distinguish omitted `params` (`None`) from explicitly supplied empty or non-empty parameters. An omitted value preserves the URL query; an explicit value replaces it.
- Exercise both mappings and ordered pairs, repeated keys, blank values, URL escaping, and a URL with no existing query. Compare normalized URL strings or `QueryParams` semantics rather than implementation details.
- Keep the repair at the narrowest request-construction layer that owns parameter merging, and avoid changing behavior when `params` is omitted.
- Add a focused regression command that runs without network access and include at least one test proving an incomplete “always preserve” or “always replace” implementation fails.
