# A parameterless WWW-Authenticate challenge serializes with a trailing space

## Situation

`/app/src` is a shallow, pinned clone of werkzeug
(`https://github.com/pallets/werkzeug`), the WSGI utility library that backs
Flask, checked out in a detached state at one specific upstream commit
(`git rev-parse HEAD` inside `/app/src` reports it) and installed in editable
(development) mode, so the code you import is exactly the checked-out source.
`git status` is clean. Python 3.12, `pytest` 9.1.1, and the packages the
project's own test suite needs are installed. There is **no network** at
trial time: everything you need is already in the image; `pip install` and
`git fetch` will not work.

## The bug

A user reports a failure completing HTTP authentication against a service:

> We authenticate with the `Bearer` scheme. Our client (an HTTP/1.1 stack
> built on h11) refuses the service's authentication challenge as malformed:
> it says the `WWW-Authenticate` header value is not a well-formed
> auth-scheme. Everything works if we swap the HTTP library.
>
> A challenge that carries only the authentication scheme — which RFC 9110
> explicitly permits, since `realm` and the other parameters are optional and
> may legitimately be omitted — is serialized to a header value with one
> extra trailing space: `Bearer ` instead of `Bearer`. A strict HTTP/1.1
> client treats it as malformed and rejects the response, so with such a
> client we cannot authenticate at all. Other single-scheme challenges, for
> example a parameterless `Basic`, behave the same way.

The defect is in werkzeug's own serialization of a `WWW-Authenticate`
challenge: when the challenge carries no parameters at all, the generated
header value ends in an unwanted space. A challenge that does carry
parameters (`realm`, `qop`, ...) or a pre-emptive token serializes correctly,
and those must keep working exactly as they do now.

## What you need to do

1. **Write your own failing reproduction first.** This is a deliverable at
   the literal path `/app/reproduce_www_authenticate_bug.py` — a plain Python
   script (the standard library plus importing `werkzeug` from the checkout
   is all you may need) that:
   - while the bug is present, demonstrates it: exits with a **non-zero**
     status and prints, to stdout or stderr, the `repr()` of the observed
     malformed header value plus a one-line explanation;
   - exits with status **0** once the serialization is correct;
   - is deterministic and self-contained: no network, no other files, no
     other processes.
   Run it before touching any code and confirm it fails.
2. **Fix the bug** in the checked-out tree at `/app/src` so that a
   `WWW-Authenticate` challenge with no parameters serializes to exactly the
   scheme, title-cased, with no trailing space (`"Bearer"`), and so that
   challenges carrying parameters or a token serialize **exactly** as they
   did before.
3. Validate with the project's own test runner, from `/app/src`:

   ```
   cd /app/src && python3 -m pytest tests/test_http.py tests/test_datastructures.py -q -p no:cacheprovider
   ```

   Both files are green at the starting commit; the project's suite must stay
   green.

## Constraints

- Network is unavailable; everything needed is installed already.
- `/app/src` is the deliverable. Repair it in place. Do not rewrite history,
  add remotes, fetch, modify build files, or change anything under the
  project's `tests/` directory. Files under `/opt/golden`, `/tests` and
  `/solution` are harness-owned; do not touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that no history was fetched or added, that no tracked file was
  deleted, that the only modified tracked files are source files under
  `src/werkzeug/` (at least one such modification present), and that
  `import werkzeug` still resolves to the checked-out tree at `/app/src`.

## What the verifier checks

1. Tree provenance: still at the pinned commit, exactly one commit in the
   clone, the upstream fix commit not present, no tracked file deleted, only
   `src/werkzeug/**` modified, `import werkzeug` resolves to the checkout,
   and the fix lives in the source of the tree itself (a wrapper outside the
   tree cannot fake it).
2. Your reproduction at `/app/reproduce_www_authenticate_bug.py`: run against
   a pristine pre-fix tree (the verifier temporarily restores the original
   buggy sources from git) it must **fail**; run against your repaired tree
   it must **pass**.
3. The project's own upstream regression test for this behaviour passes (it
   is kept out of the tree at `/opt/golden/test_http.py` and copied in by the
   verifier, then the tree's own copy is restored).
4. The project's own suite still passes: `tests/test_http.py` and
   `tests/test_datastructures.py`.
5. Hidden cases over parameterless-challenge shapes the upstream test does
   not use (other schemes, case variants, strict token grammar), plus a guard
   that parameterised and token challenges are unaffected.

Deliverables: the repaired `/app/src` tree and
`/app/reproduce_www_authenticate_bug.py`.