---
name: httpx-url-query-regression
description: Diagnose and regression-test HTTPX URL construction changes, especially explicit query-parameter replacement and preservation semantics.
---

# HTTPX URL/query regression workflow

Use this skill when diagnosing or repairing HTTPX request URL construction, particularly
changes to how `Request(..., params=...)` interacts with a query already in the URL.
It is reusable for offline regressions in this boundary; it is not a general HTTP client
testing guide.

1. Pin the HTTPX source revision and reproduce through the public `httpx.Request` or
   client-building API. Do not rely on private URL helpers alone.
2. Treat the three states distinctly: omitted `params` preserves the parsed query,
   while an explicitly supplied empty or non-empty value supplies the complete query.
3. Cover mappings and ordered pairs, repeated keys, blank values, escaping, fragments,
   and URLs with no prior query. Assert serialized URL behavior and request invariants,
   not a particular internal implementation.
4. Keep changes at the request-construction layer that owns this policy. Include a
   regression proving that both “always merge/preserve” and “always replace” repairs
   are incomplete, and run it with no network access.
