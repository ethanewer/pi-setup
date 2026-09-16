# no_proxy host matching must respect domain boundaries

## Situation

`/app/src` is a shallow, pinned clone of the requests project
(`https://github.com/psf/requests`), checked out at upstream commit
`3816cfa1abd42dca21b9e837f26c59b246016aaf` and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
source. Python 3.12, the pinned dependency set and pytest are installed. There
is **no network** at trial time: `pip`, `git fetch` and any external HTTP call
fail during your session. Everything you need is already in the image.

## The bug

When a `no_proxy` list is supplied (as an argument or through the
environment), the library decides whether a URL should bypass the configured
proxies. That decision is wrong at domain boundaries:

- A host that merely **ends with** an entry is treated as though it were that
  entry. With `no_proxy = "localhost"` the host `prelocalhost` is wrongly
  excluded from proxying, even though it is a different machine, just as
  `badexample.com` would be excluded by a `no_proxy = "example.com"`. The
  matcher compares with a bare `endswith` instead of requiring an exact
  match first and then only real subdomains (a leading-dot boundary).

`python3 /app/probe_no_proxy.py` prints the current (buggy) behaviour: the
first line is `True` for `prelocalhost` where the correct answer is `False`.
The probe also shows the second failing family: entries pinned to a port
(`.svc.internal:9443`) or entered with a leading dot are not matched against
their own hostname/host:port the way they should be.

A one-liner that shows the greedy-direction bug:

```
python3 -c "from requests.utils import should_bypass_proxies; print(should_bypass_proxies('http://prelocalhost/', no_proxy='localhost'))"
```

prints `True`; the correct answer is `False`.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so proxy-bypass decisions
respect domain boundaries, following the convention the rest of the Python
proxying world uses (CPython's `urllib.request`, curl, wget):

- a host is exempt only when it **is** the entry (the bare hostname, with or
  without the entry's port), or is a genuine subdomain of the entry; hosts
  that merely share a suffix must not be exempt;
- an entry entered with a leading dot (`.example.com`) matches the bare
  host `example.com` as well as every subdomain of it.

Everything else keeps its current behaviour: exact hostname and host:port
matches, IP-address and CIDR entries (including `192.168.0.0/24`-style
ranges), blank/whitespace-separated entries, and hostless URLs.

Reproduce, localise and fix the problem in the real tree, then drive your work
with the project's own test runner from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_utils.py -q -p no:cacheprovider
```

The project's own utils test file is green at the pinned commit; keep it that
way. Add your own tests if that helps you (for example other suffix-lookalike
hosts, dotted entries with ports, or the end-to-end `get_environ_proxies`
path), but the verdict on your fix is made by the verifier, which runs the
upstream regression test for this behaviour plus hidden cases of its own.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone under `/app/src` is the deliverable. Change only what the fix
  requires, in place. Do not rewrite history, add or reconfigure remotes,
  fetch, or modify build or configuration files. Files under `/opt/golden`,
  `/tests` and `/solution` are harness-owned; do not touch them.
- The verifier also asserts that the working tree stays at the pinned commit,
  that the only tracked file you changed is the minimal source surface, and
  that no new files were added inside the package.

## What the verifier checks

1. The tree is still at commit `3816cfa1abd42dca21b9e837f26c59b246016aaf`,
   with only the minimal tracked source file modified and no new files inside
   the package.
2. The project's own upstream regression test for this bug passes.
3. The project's own existing proxy tests in `tests/test_utils.py` still pass.
4. Hidden cases over inputs the upstream test does not use pass: suffix
   lookalikes around a plain host entry, dotted and port-pinned entries
   through both the argument channel and the `NO_PROXY` environment channel,
   and the end-to-end `get_environ_proxies`/`resolve_proxies` path.

Deliverable: the repaired `/app/src` tree.