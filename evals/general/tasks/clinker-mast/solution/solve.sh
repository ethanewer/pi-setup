#!/bin/bash
# Oracle for clinker-mast: implements the missing HTTPX retrying-transport
# feature inside the pinned checkout at /app/src, exactly as a competent
# agent would, then documents it in the /app/feature.md deliverable.
# It NEVER reads /tests.
set -euo pipefail

SRC=/app/src

# 1) Ship the implementation as a new transport module of the package.
cp /solution/retry_impl.py "$SRC/httpx/_transports/retry_impl.py"

# 2) Export it from the transports subpackage and the package top level,
#    keeping the upstream export invariant: every public name is in `__all__`,
#    and `__all__` stays sorted with str.casefold (the library's own
#    test_exported_members.py asserts exactly that).
python3 - "$SRC" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
new_names = ["AsyncRetryTransport", "RetryTransport"]

transports_init = src / "httpx" / "_transports" / "__init__.py"
text = transports_init.read_text()
if "RetryTransport" not in text:
    text = text.replace(
        "from .wsgi import *",
        "from .retry_impl import *\nfrom .wsgi import *",
    )
    transports_init.write_text(text)


def insert_sorted(text: str, new_name: str) -> str:
    """Insert one quoted name into the __all__ list, keeping casefold order."""
    if ('"' + new_name + '"') in text:
        return text
    start = text.index("__all__ = [")
    end = text.index("\n]", start)
    block = text[start:end]
    existing = re.findall(r'"([^"]+)"', block)
    anchors = [n for n in existing if n.casefold() < new_name.casefold()]
    if anchors:
        anchor = max(anchors, key=str.casefold)
        line = '    "%s",' % new_name
        text = text.replace('    "%s",' % anchor, '    "%s",\n%s' % (anchor, line), 1)
    else:
        line = '    "%s",\n' % new_name
        text = text[:start] + "__all__ = [\n" + line + text[start + len("__all__ = ["):]
    return text

for name in new_names:
    transports_init.write_text(
        insert_sorted(transports_init.read_text(), name)
    )

for name in new_names:
    top_init = src / "httpx" / "__init__.py"
    top_init.write_text(insert_sorted(top_init.read_text(), name))
PY

# 3) Prove the feature against the library's own relevant tests.
cd "$SRC"
python3 -m pytest tests/test_exported_members.py tests/client/test_event_hooks.py tests/client/test_client.py -q -p no:cacheprovider

# 4) Prove the observable contract end to end in a fresh interpreter.
python3 - <<'PY'
import httpx

assert hasattr(httpx, "RetryTransport")
assert hasattr(httpx, "AsyncRetryTransport")
assert httpx.RetryTransport is not None
assert httpx.AsyncRetryTransport is not None

# transport error -> retried -> success
calls = {"n": 0}

def flaky(request):
    calls["n"] += 1
    if calls["n"] == 1:
        raise httpx.ConnectError("boom")
    return httpx.Response(200, content=b"ok")

with httpx.Client(
    transport=httpx.RetryTransport(
        transport=httpx.MockTransport(flaky), max_attempts=3
    )
) as client:
    response = client.get("https://example.com/")
assert response.status_code == 200
assert calls["n"] == 2

# retryable status -> retried -> success
calls = {"n": 0}

def five_oh_three(request):
    calls["n"] += 1
    if calls["n"] == 1:
        return httpx.Response(503)
    return httpx.Response(200, content=b"back")

transport = httpx.RetryTransport(
    transport=httpx.MockTransport(five_oh_three), max_attempts=2
)
with httpx.Client(transport=transport) as client:
    response = client.get("https://example.com/")
assert response.status_code == 200
assert calls["n"] == 2

# max_attempts exhausted -> last TransportError surfaces
calls = {"n": 0}

def always_down(request):
    calls["n"] += 1
    raise httpx.ReadTimeout("down")

try:
    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(always_down), max_attempts=3
        )
    ) as client:
        client.get("https://example.com/")
except httpx.TransportError:
    pass
else:
    raise AssertionError("expected TransportError to surface")
assert calls["n"] == 3

print("oracle behavioural self-check ok")
PY

# 5) Write the deliverable: a feature document naming the classes and the
#    in-tree location.
cat > /app/feature.md <<'MD'
# HTTPX retrying-transport feature

**Class names:** `httpx.RetryTransport` (sync) and
`httpx.AsyncRetryTransport` (async).

**Where it lives:** implemented in the HTTPX checkout at `/app/src`, in
`httpx/_transports/retry_impl.py`, and exported from
`httpx/_transports/__init__.py` and `httpx/__init__.py`.

**What it does:** HTTPX itself deliberately never retries failed requests.
These two transports wrap any inner transport and re-issue the request when
an attempt fails transiently:

- the attempt raised an `httpx.TransportError` (connect/read/write/
  protocol/timeout errors), or
- the attempt produced a response whose status is retryable:
  429, 500, 502, 503 or 504.

The number of attempts is capped by `max_attempts` (default 3, at least 1).
When a retryable response carries a numeric `Retry-After` header, that many
seconds elapse before the next attempt, and a response that is abandoned for
a retry has its stream closed so no connection leaks.  On the final attempt
the caller receives the real outcome: the last error is raised or the last
response is returned as-is.

**Usage:**

```python
import httpx

transport = httpx.RetryTransport(
    transport=httpx.MockTransport(flaky_handler),
    max_attempts=3,
)
with httpx.Client(transport=transport) as client:
    response = client.get("https://example.com/")
```

Same shape with `httpx.AsyncRetryTransport` and `httpx.AsyncClient`.

**Design notes:** the wrapper implements `httpx.BaseTransport` /
`httpx.AsyncBaseTransport`, so it slots into `httpx.Client(transport=...)`
and `httpx.AsyncClient(transport=...)` like any other transport, and retries
are invisible to the client-level event hooks.  When no inner transport is
supplied the standard network transports (`HTTPTransport` /
`AsyncHTTPTransport`) are used, so the wrapper is a drop-in replacement.
MD

# 6) Final deliverable sanity (no /tests involved).
python3 - <<'PY'
import os

path = "/app/feature.md"
assert os.path.isfile(path)
text = open(path, encoding="utf-8").read()
assert "RetryTransport" in text
assert "AsyncRetryTransport" in text
assert "/app/src" in text
print("deliverable ok")
PY

echo "clinker-mast oracle done"