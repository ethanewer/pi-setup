# Fix aiohttp: a crafted `Forwarded` request header hangs the server forever

## The bug

The `aiohttp` web framework installed in this container has a parsing defect
that a single crafted HTTP request header can exploit to freeze the entire
server process.

`Request.forwarded` — the property a handler reads to learn the parsed
`Forwarded` header from an inbound request — **never returns** for certain
header values. When a `Forwarded` header line ends with an empty or
malformed element, for example `Forwarded: ; a` or a bare trailing token
with no `=` sign such as `Forwarded: a`, accessing `request.forwarded`
enters an infinite loop and spins at 100% CPU forever. Because such code
runs on the single-threaded event loop, one hostile request wedges the
whole worker: every handler that merely touches `request.forwarded` stalls
indefinitely, and an attacker who can send one such header can hold a
connection open forever.

You can reproduce it right now with only the installed packages — no
network and no server, the request is constructed in memory:

```
python3 - <<'PY'
from multidict import CIMultiDict
from aiohttp.test_utils import make_mocked_request

req = make_mocked_request("GET", "/", headers=CIMultiDict({"Forwarded": "; a"}))
print(dict(req.forwarded[0]))
PY
```

Today this never prints: run it under `timeout 10 ...` and the process is
killed. Your job is to make aiohttp parse these headers correctly instead
of spinning.

## Environment

- `/app/src` is a real, SHA-pinned source checkout of aiohttp (a shallow
  git clone, checked out on the revision the image was built with — leave
  it on that revision; do not create git commits or move the checkout).
- The library is editable-installed from that checkout in pure-Python mode
  (`AIOHTTP_NO_EXTENSIONS=1`): any edit you make to the Python source under
  `/app/src/aiohttp/` is live in `import aiohttp` immediately, in every
  fresh interpreter.
- Installed test toolchain (all pinned): pytest 9.1.1, pytest-asyncio 1.4.0,
  pytest-aiohttp 1.1.1, pytest-timeout 2.4.0, freezegun 1.5.5, coverage 7.15.4.
- Network access at trial time is not guaranteed; in particular, do not
  rely on installing packages or fetching code from the internet.
  Everything you need is already on disk.
- Do not modify anything under `/app/src` other than the aiohttp library
  source that your fix actually requires, and do not add any new files to
  the checkout — the grader verifies that the upstream working tree is
  otherwise untouched.

## What "correct" means

The fix must live in the aiohttp source tree at `/app/src` — it has to be a
real repair of the library, not a workaround in a script or a wrapper.
Satisfy all of the following:

1. The reproducer above must terminate and print `{}`.
2. Reading `request.forwarded` must never hang, for any header value — in
   particular all of the following single-header values must terminate:
   `a`, `; a`, `for=1.2.3.4; a`, `for=_real; x`, `bad; for=_real`,
   `for=1.2.3.4; ;a`, `for=_real;x`, `for=1.2.3.4; ; ; a`,
   `for="a;b"; somebody`.
3. The parse result for such a value keeps the valid elements that appear
   before the first malformed/empty tail, and stops there — nothing after a
   wrongly-formed element may be attributed to the request. Concretely:
   - `a` → `{}`
   - `; a` → `{}`
   - `for=1.2.3.4; a` → `{"for": "1.2.3.4"}`
   - `for=_real; x` → `{"for": "_real"}`
   - `bad; for=_real` → `{}`
   - `for=1.2.3.4; ;a` → `{"for": "1.2.3.4"}`
   - `for="a;b"; somebody` → `{"for": "a;b"}`
   (dict values compare case-sensitively; existing behaviour for valid
   headers — quoted values, ports, mixed case, multiple headers — must be
   unchanged.)
4. The project's own existing `Forwarded` parsing tests stay green:
   ```
   cd /app/src && python3 -m pytest -q -p no:cacheprovider tests/test_web_request.py -k forwarded
   ```
5. Write a short report at `/app/fix-report.md` (plain text or Markdown,
   at least a few sentences) that a maintainer could act on. It must state
   precisely where the fault lives — the module and the parsing step that
   fails to make progress on a header that ends with an empty or malformed
   element — naming that file by its full path under `/app/src/aiohttp/`,
   the minimal change you made, and how you verified it.

The grader checks the fixed tree directly (it runs aiohttp's own regression
tests against your checkout, plus additional hidden cases on the same code
path), so make the fix in the source and leave it on disk.

## Notes

- `cpus = 1`; keep any invocations sequential.
- Debugging hint: the unconditional scan for the next `;` separator is not
  the problem — the problem is what happens when that scan finds *nothing*,
  because a header can end with an empty or malformed element instead of a
  complete `name=value` pair. Trace what the parser does with the value it
  just looked at when there is no next separator, and what the loop position
  does afterwards for `Forwarded: ; a` on the last (empty) element.
- When you think you are done, run the reproducer under `timeout`, run the
  test command in requirement 4, and try a few of the header values listed
  above in a fresh `python3` before writing the report.