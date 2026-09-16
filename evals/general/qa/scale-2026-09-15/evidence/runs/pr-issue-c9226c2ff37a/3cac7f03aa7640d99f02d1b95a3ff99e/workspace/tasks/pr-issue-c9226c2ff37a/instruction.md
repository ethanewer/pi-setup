Update HTTPX request URL construction so that explicit query parameters have replacement semantics.

Modify `/app/httpx/_models.py` only as needed. When a caller supplies `params` (including an empty mapping), the resulting request URL must use those parameters instead of retaining query parameters already present in the URL. When `params` is omitted, the original URL query must be preserved.

The behavior must work for mappings and ordered sequences of pairs, preserve repeated keys and blank values, and continue to percent-encode parameter names and values correctly. It must not make network requests or change unrelated request behavior.

Acceptance criteria:

1. `httpx.Request("GET", "https://example.com/items?old=1", params={})` has no query string.
2. A non-empty mapping replaces an existing query rather than merging with it.
3. Ordered pairs, repeated keys, and blank values are represented correctly and in order.
4. Omitting `params` preserves the original query exactly.
5. Existing request-model tests continue to pass; do not solve this by changing public URL parsing or by hard-coding these examples.
