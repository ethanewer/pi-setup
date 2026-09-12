# Fix curl crashing on a comment-only credentials file

## Environment

`/app/src` is a real upstream checkout of **curl** (the command-line tool and
libcurl library), pinned to a single snapshot: the working tree is `HEAD` of
the clone at commit `fd8c409d6ab7367051d04646a31e976e3db0c6ed`, and it is the
latest revision at which the defect described below still exists. The checkout
is **shallow and detached** — there is only one commit in the clone, so there
is no history to consult and nothing to fetch. The tree is still fully
writable and buildable.

The project is already configured and built in the image:

- `/app/src/src/curl` — the build output binary (a debug build, matching the
  upstream developer setup),
- `/app/src` — the full source, test data and test harness; the test harness
  under `/app/src/tests` is built (test servers, unit-test bundles, libtest
  tools),
- toolchain: gcc, autoconf/automake/libtool, openssl dev headers, perl
  5.38, `gdb`, `strace`, python3.12.

There is **no network** in this container. Everything you need is already on
disk; do not attempt to download anything.

## The problem

When curl is told to read credentials from a `.netrc` file that contains
**only comment lines** — no `machine`, `login` or `password` entries — the
whole program dies immediately with a segmentation fault, on startup, before
any connection is attempted. The file `/app/src/src/curl` crashes with
`Segmentation fault` and exit status `139`.

This is deterministic: it does not depend on the URL, on the server, or on
reachability. A credentials file whose entire raw content consists of comment
lines and whose final line does not end in a newline is enough — for example
the content `# only a comment line` with no trailing newline. Any script that
passes `--netrc` together with such a credentials file dies instantly.

(The precise trigger matters: while the file is loaded, comment lines are
discarded early, so a comment-only file leaves nothing to parse. A file that
ends with a newline, or a genuinely empty file, gives the parser a final
empty line to chew on and does not crash — only the no-trailing-newline
comment-only shape does.)

The correct behaviour — which the upstream project later adopted — is that a
credentials file with nothing to match simply contributes **no credentials**:
curl should proceed with the request anonymously, exactly as if no usable
entries existed, and exit `0`.

Your job:

1. reproduce the crash,
2. localise and **fix the real bug in the source tree** — the fixed tree must
   keep building with the project's own build system, and
3. rebuild the binary so the fixed behaviour is in `/app/src/src/curl`,
4. write up the root cause in `/app/diagnosis.md`.

## Reproducing

Start a throwaway loopback HTTP server (there is no external network, but
loopback works):

```sh
python3 - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'-foo-'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', 8890), H).serve_forever()
PY
```

Then:

```sh
printf '# only a comment line' > netrc
/app/src/src/curl --netrc --netrc-file ./netrc http://127.0.0.1:8890/
```

Observations at the current tree state:

- the `curl` binary is killed by SIGSEGV (`Segmentation fault`, exit `139`),
  and it happens before any byte is sent to the server — a comment-only
  credentials file without a trailing newline dies, as does the reproducer
  below.

Expected behaviour after your fix:

- exit code `0`, and the server body `-foo-` printed on stdout — the request
  completes anonymously because the credentials file contributed nothing.

Notes:

- the crash is specific to loading a credentials file whose parsed content is
  empty; files with real `machine` entries must keep working exactly as
  before,
- the fix belongs in the tree, not in the command line: do not make the
  reproducer pass by adding flags like `--netrc-optional`, by wrapper
  scripts, or by any other workaround that would leave the binary crashing,
- a fix may not paper over the symptom (e.g. by weakening the build, deleting
  code paths, or turning checks off).

## Verifying your fix

Rebuild incrementally (only changed files recompile — this is fast):

```sh
make -C /app/src
```

Then run the project's own test suite for the affected area and a couple of
basic HTTP requests. From `/app/src/tests`:

```sh
./runtests.pl -n 1 2005 2309 1304
```

- test `1304` is the project's unit test for the credential-file scanner,
- tests `2005` and `2309` exercise `.netrc` handling over real HTTP,
- test `1` is a plain HTTP GET.

All four must pass. Do not modify, delete, rename or disable any test or any
test data, and do not alter the test harness: your fix must make the real
code correct, not the tests weaker. Your reproducer above must also now
succeed (exit `0`, body printed).

## Deliverables

- the **fixed source tree** under `/app/src` (the defect corrected at its
  root, nothing else changed),
- the **rebuilt binary** at `/app/src/src/curl` (debug build, reflecting your
  fix),
- a root-cause write-up at **`/app/diagnosis.md`**: what triggers the crash,
  the precise mechanism (which parsed state becomes invalid and where the
  invalid state is consumed), and what change fixes it. Mention the
  credentials-file feature by name.

The write-up will be read by a human reviewer; the tree and binary are graded
by an automated verifier (behavioural checks over HTTP plus the project's own
test runner). Leave the rest of the tree exactly as upstream has it: the
verifier rejects unrelated changes.