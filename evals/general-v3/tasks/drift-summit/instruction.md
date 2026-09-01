# drift-summit — session-operator tooling drill

You are the operator of an isolated evaluation lab container. Several long-lived
tools and services were set up to support a testing session, and the session
journal must be assembled. Everything runs in one Linux container (Ubuntu
24.04, `bench-base`). You operate as root; the lab's *session user* is `ops`
(local account, no shell password).

Your job: build the session infrastructure described below and produce **four
artifacts** in `/app`:

1. `/app/session.log` — the session journal (exact format below)
2. `/app/daemons.pid` — PIDs of the two long-lived daemons
3. `/app/debug.txt` — debugger stepping transcript (program-mode trace)
4. `/app/sudo.txt` — sudo-grant enumeration for `ops` + restricted content

You must also leave reusable tools in `/app`:
`/app/monitor.py`, `/app/step_trace.py`, `/app/analyze_events.py` (specs below).

The verifier runs **after** your session ends, **in this same container**. All
processes you start must still be running, and every referenced file must exist,
at that point.

---

## Lab layout (pre-existing, do not modify)

| Path | Purpose |
| --- | --- |
| `/opt/smp/smp_debug.py` | interactive instruction-level debugger (see Part C) |
| `/srv/programs/fib.smp` | visible SMP program image |
| `/srv/site/` | web root for the HTTP daemon (`index.html` inside) |
| `/srv/events/current.ndjson` | live event stream (newline-delimited JSON) |
| `/srv/monitor/` | output dir for the long-running monitor |
| `/srv/restricted/summary.txt` | root-only file (mode 600), readable only via sudo |
| `/etc/sudoers.d/ops` | sudo grants for user `ops` (mode 440) |
| user `ops` | session user (home `/home/ops`) |

Installed tooling: `python3` (3.12), `tmux`, `openssh-server` (host keys already
generated, `/run/sshd` exists), `procps`, `curl`, `sudo`, `runuser`.

---

## Part A — long-lived daemons

Start and **keep running** two daemons. They must survive your session and still
respond when the verifier runs.

1. **SSH daemon** on `0.0.0.0:2222`:
   `/usr/sbin/sshd -D -p 2222`
2. **HTTP daemon** on `0.0.0.0:8080` serving `/srv/site/`:
   `python3 -m http.server 8080 --bind 0.0.0.0 --directory /srv/site`

Rules that actually matter for survival: detach them from your shell
(`setsid ... &` or `nohup ... &` plus `disown`), redirect stdout/stderr to log
files under `/var/log/`, and close stdin with `</dev/null`. Do **not** put them
in the foreground of any terminal that will exit.

Then write `/app/daemons.pid`, exactly two lines:

```
sshd <pid>
httpd <pid>
```

Use the real PIDs of the running listeners (e.g. from `pgrep`). The verifier
checks that these processes exist and that both ports answer.

## Part B — tmux pane + long-running monitor

1. Create a detached tmux session with a **single window, single pane**, named
   `ops-session`:
   `tmux new-session -d -s ops-session -x 200 -y 50`
2. Write the monitor script `/app/monitor.py` (Python 3, executable). Behavior:
   loop forever, every **2 seconds** append to `/srv/monitor/tally.out` one line
   ```
   <seq> <epoch> alive
   ```
   where `<seq>` is a 0-based consecutive counter and `<epoch>` is
   `time.time()` with 6 decimals. Keep it running indefinitely (no exit path).
3. Launch it **inside that specific pane** — target pane `ops-session:0.0`
   explicitly, e.g.:
   `tmux send-keys -t ops-session:0.0 "exec python3 /app/monitor.py" Enter`
   The `exec` makes the pane process *be* the monitor. Sending it to the wrong
   pane or session counts as failure. Do not kill the session afterwards.

The monitor must still be running in pane `ops-session:0.0` at verification
time, and `/srv/monitor/tally.out` must keep growing.

## Part C — driving the program-mode debugger

`/opt/smp/smp_debug.py` is an interactive **instruction-level** debugger for the
SMP machine: an 8-register (R0–R7) stack machine with a 16-bit address space.
It is driven **entirely by line commands on stdin** (one command per line, EOF
or `quit` ends it). When stdin is not a terminal it prints no prompts/banners —
a clean transcript.

SMP program images are text files; each line is `<hex-address> <OP> [operand]`,
addresses contiguous from a base (all provided programs start at `0x0000`,
`#` starts a comment). The instruction set (operand stack + registers):

| OP | meaning |
| --- | --- |
| `PUSH n` | push integer `n` |
| `LOAD r` / `STORE r` | push `Rr` / pop into `Rr` (r = 0..7) |
| `POP` | discard top of stack |
| `ADD SUB MUL DIV` | pop b, pop a, push a-op-b |
| `DUP` / `SWAP` | duplicate top / swap top two |
| `JMP a` | jump to hex address `a` |
| `JZ a` / `JNZ a` | pop; jump if zero / nonzero |
| `OUT` | pop and print `out <value>` |
| `HALT` | stop execution |

Debugger commands (line commands):

| command | effect |
| --- | --- |
| `load <path>` | load + validate a program image |
| `list` | print the loaded program |
| `step` (alias `s`) | execute exactly one instruction |
| `trace <n>` (alias `t`, `si`) | execute up to `<n>` instructions, one per line |
| `run` | execute until `HALT` |
| `regs` (alias `r`) | print `pc`, halted flag, R0–R7, stack depth |
| `stack` (alias `st`) | print the operand stack (top first) |
| `help` / `quit` | help / exit |

Transcript contract (used by the verifier):

- `load` prints on success: `program <path> loaded: N instructions base=0x0000 max=0xXXXX`
- every executed instruction prints exactly: `exec 0xXXXX` (its address)
- executing `HALT` prints: `halt 0xXXXX` (no further execution happens)
- a `trace`/`run` that ends without halting prints: `stopped pc=0xXXXX after N steps`
- invalid commands produce a line starting with `error:`

Write the driver `/app/step_trace.py` (Python 3, executable) that takes optional
arguments `<program>` and `<steps>` (defaults: `/srv/programs/fib.smp` and `16`),
**feeds the debugger a piped sequence of line commands on stdin**, e.g.:

```
load <program>
regs
trace <steps>
regs
quit
```

and prints the debugger's transcript to stdout unchanged.

Produce the deliverable by running your driver with defaults:

```
python3 /app/step_trace.py > /app/debug.txt
```

`/app/debug.txt` must contain multiple executed addresses (the first 16 of the
`fib.smp` execution, exactly matching the machine's real stepping) and a
`stopped`/`halt` line. The driver must also work on **other** SMP program files
passed as arguments — the verifier feeds it new programs.

## Part D — marker-message detection

The event stream `/srv/events/current.ndjson` is newline-delimited JSON with
fields such as `ts`, `svc`, `level`, `message`, `status`, `note`.

An event record is **error-marked** when any of these marker substrings occurs,
**case-insensitively**, in its `message` or `status` field (search those two
fields only — text in other fields such as `note` is irrelevant, even if it
contains a marker word):

```
error   fault   timeout
```

Examples: `status: "timeout"` marks; message `"ERROR queue flooded"` marks;
message `"timed_out_gracefully"` does **not** mark (`timeout` is not a
substring); a marker word only inside `note` does not mark; `status: 200` or a
missing field does not mark.

Write the reusable analyzer `/app/analyze_events.py` (Python 3, executable):

```
usage: python3 /app/analyze_events.py <path>      # or "-" for stdin
```

It reads the NDJSON, **preserves every error-marked record in input order**
annotated with an extra `_markers` field (sorted list of the marker substrings
found in that record), and prints this report to stdout:

```
total=<T>
error_marked=<E>
marker_occurrences=<K>
---preserved---
<json line per preserved record, original fields intact plus "_markers": [...], one per line, input order>
---end---
```

`T` = records read, `E` = error-marked records, `K` = total number of marker
occurrences across marked records (sum of `len(_markers)`), `_markers` lists
unique markers per record, sorted. Missing or dropped error records, or
wrongly-marked clean records, all change these numbers.

Run it on the live stream and embed the **verbatim output** in the journal (Part F).

## Part E — sudo grants for the session user

User `ops` holds a restricted sudo grant in `/etc/sudoers.d/ops` (read it if
you like, but the point is to **inspect the sudo grant** as an operator).

1. Enumerate the commands `ops` may run via sudo. Working as root, the direct
   way is:
   ```
   sudo -n -l -U ops
   ```
   (alternatively: `runuser -u ops -- sudo -n -l`). Parse out the configured
   command list (the tokens after `NOPASSWD:`).
2. Write `/app/sudo.txt` in exactly this format — one `allowed-cmd:` line per
   granted command using its canonical form exactly as configured (do not add
   or drop trailing arguments, and do not reorder the args), then the content
   of `/srv/restricted/summary.txt` as a single `summary:` line:

   ```
   allowed-cmd: <granted command 1>
   allowed-cmd: <granted command 2>
   ...
   summary: <content of /srv/restricted/summary.txt>
   ```

3. The restricted file is mode 600 root-only — `ops` cannot read it directly.
   Obtain the content by **executing one of the granted elevated commands as
   `ops`**, e.g.:
   ```
   runuser -u ops -- sudo -n /usr/bin/head -c 4096 /srv/restricted/summary.txt
   ```
   and put that content on the `summary:` line. (Use `sudo -n`; `ops` has no
   password.)

The verifier compares your `allowed-cmd:` set exactly against the sudoers
configuration, and the `summary:` content against the file.

## Part F — session journal

Write `/app/session.log` with exactly this structure:

```
session-log v1
host=<hostname of this container>
tmux-session=ops-session
tmux-pane=0.0
sshd_pid=<pid from /app/daemons.pid>
httpd_pid=<pid from /app/daemons.pid>
=== marker report ===
<verbatim stdout of: python3 /app/analyze_events.py /srv/events/current.ndjson>
=== end marker report ===
```

All values must be the real ones from this container.

---

## Hard rules

- Create the artifacts at exactly these paths with exactly these formats.
- Do not modify anything under `/srv` (no extra files, no permission changes),
  do not edit `/etc/sudoers.d/`, `/etc/sudoers`, do not kill or restart
  services that are part of the scenario.
- Everything you start must survive your session ending.
- `/app/monitor.py`, `/app/step_trace.py`, `/app/analyze_events.py` must be
  runnable on **new** inputs (monitor format fixed; driver takes a program path
  + step count; analyzer takes a path or `-`).
- Output formats are byte-exact; the verifier compares your numbers and traces
  against independently recomputed references.