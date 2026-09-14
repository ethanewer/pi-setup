# Fetching two IMAP folders that differ only by letter case reads mail from the wrong folder

## The bug

You are working on **curl**, the real command-line transfer client, checked out from its
own upstream source tree at `/app/curl`. The tree is pinned at a specific upstream
commit and is already configured and built — the binary is `/app/curl/src/curl`.

A user reports the following, and it is true:

> "I fetch two IMAP URLs in a single curl command whose folder paths differ only by
> capitalisation, for example one message from `/Private/` and one from `/private/`.
> Both URLs succeed with exit code 0 — no error, no warning — but the second message
> turns out to have come from the first folder. My mail server's log shows my client
> never even asked for the second folder, even though a server treats `Private` and
> `private` as completely different folders."

Your job: find the cause in the curl source, fix it, and prove both directions.

## Environment

- `/app/curl` — the curl source tree (a git checkout at a pinned upstream commit, all
  build machinery already run: `./configure --with-openssl --enable-debug` was executed
  during image build, the test harness is built under `/app/curl/tests`).
- Rebuild incrementally with `cd /app/curl && make -j1` (one CPU; a source change to
  `lib/` takes a few minutes).
- The project's own test harness is runnable: `cd /app/curl/tests && ./runtests.pl -n <num>`.
- Python 3 is installed. OpenSSL, the autotools toolchain and the Perl harness are installed.
- There is **no network** in this environment. Everything you need is already on disk.
  `apt`/`pip`/`git fetch` will not work at trial time.
- Do not modify anything outside `/app/curl` and `/app/reproduce_bug.sh`.
- `/opt/curl.buggy` is a pristine copy of the pre-fix binary (used by the grader); leave it untouched.

## Deliverable 1: your own failing reproduction — `/app/reproduce_bug.sh`

Write this script **before** changing any source. It is an executable bash script with
this exact contract:

1. It takes one optional argument: the path of the curl binary under test. Default:
   `/app/curl/src/curl`.
2. It is fully self-contained: it runs its own minimal IMAP server on `127.0.0.1`
   (any port it chooses) that logs every command the client sends, then runs the curl
   binary under test against **two IMAP URLs in a single invocation** whose mailboxes
   differ **only in letter case** (same letters otherwise), using `-u user:secret`.
3. It inspects the server-side command transcript and exits with status **0 exactly when
   the curl under test issued a fresh mailbox-selection command for the second,
   case-differing mailbox (correct behaviour), and **nonzero** when the second fetch
   proceeded while the first mailbox was still selected (the bug).
4. It prints a short human-readable verdict to stdout and cleans up after itself —
   no stray processes, the IMAP port is freed when it exits.
5. It must not rely on the network or on an external IMAP server.

The reproduction must genuinely fail on the unfixed code and pass on the fixed code —
that is exactly what makes it a reproduction. A script that hardcodes its verdict
instead of running curl is worthless and will be scored as such.

## Deliverable 2: the fix

Locate the cause in the source under `/app/curl`, fix it, and rebuild with
`make -C /app/curl -j1`. The rebuilt `/app/curl/src/curl` is the binary that will be
tested. The fix must live in the source code of the project: a swapped binary, a
wrapper script, or an environment hack does not count and will be detected.

When your work is done, running `/app/reproduce_bug.sh` with no arguments must exit 0.

## How your work will be graded

Your reproduction script is run three ways:

- against `/opt/curl.buggy` (the pristine pre-fix binary): it **must fail** there;
- against your rebuilt `/app/curl/src/curl`: it **must pass**;
- the grader then force-rebuilds `/app/curl` from source and re-runs the checks with the
  freshly built binary, so the fix must be a real change to the project's source code,
  not a swapped binary or a wrapper.

Then the grader runs the project's own test harness against your rebuilt binary:

- the project's IMAP regression test (test 804, from a canonical copy restored over
  whatever is in the tree) — must pass;
- existing project tests that must still pass: 1, 10, 800, 801, 802, 803, 805, 806;
- extra checks with mailbox inputs the regression test does not use: three case-variants
  of one folder in a single invocation, the same folder fetched twice (re-selection must
  still be skipped), and `INBOX`/`iNbOx` mixed case (re-selection must still be skipped
  for the case-insensitive inbox).