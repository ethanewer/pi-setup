#!/usr/bin/env python3
"""Apply the fix for the send()-timeout bug to /app/src/httpx/_client.py.

This is the oracle's implementation of the fix, written to the same effect as
the upstream resolution of the issue: before a request is dispatched,
BaseClient._set_timeout() writes the client's configured timeout into the
request's extensions when the request does not already carry a timeout, and
both Client.send() and AsyncClient.send() call it. Manually built Request
instances therefore honour the client-level timeout again, while requests
with their own timeout remain untouched.

The edit is performed as a guarded textual transformation so that it only
applies to the pristine parent revision and fails loudly if the file already
differs from it.
"""
import sys
from pathlib import Path

PATH = Path(sys.argv[1] if len(sys.argv) > 1 else "/app/src/httpx/_client.py")
text = PATH.read_text(encoding="utf-8")

assert "_set_timeout" not in text, "fix already present; refusing to re-apply"

# 1) Add the helper to BaseClient, immediately before the Client class.
marker = "class Client(BaseClient):\n"
assert text.count(marker) == 1, "unexpected shape for the Client class marker"
helper = '''    def _set_timeout(self, request: Request) -> None:
        if "timeout" not in request.extensions:
            timeout = (
                self.timeout
                if isinstance(self.timeout, UseClientDefault)
                else Timeout(self.timeout)
            )
            request.extensions = dict(**request.extensions, timeout=timeout.as_dict())


'''
text = text.replace(marker, helper + marker, 1)

# 2) Call it from both Client.send and AsyncClient.send, immediately before
#    the request is handed to the auth handling.
call_site = "        auth = self._build_request_auth(request, auth)\n"
assert text.count(call_site) == 2, (
    "expected exactly two _build_request_auth call sites (sync + async); "
    "found %d" % text.count(call_site)
)
replacement = (
    "        self._set_timeout(request)\n\n"
    + call_site
)
text = text.replace(call_site, replacement)

PATH.write_text(text, encoding="utf-8")

# 3) Prove the patch landed: one definition and two call sites.
final = PATH.read_text(encoding="utf-8")
assert final.count("_set_timeout") == 3, final.count("_set_timeout")
assert final.count("def _set_timeout") == 1
print("fix applied to %s" % PATH)