# culvert — a settings-resolution CLI written in the Go language

You are the tooling engineer for the **mast** relay service. The one thing every
on-call person needs is a command that explains *which* configuration the
service will actually run with, where each value came from, and whether the
checked-in config file is sound. That command is `culvert`, and you are going to
write it from scratch in the **Go programming language** (the toolchain is the
`golang-go` package, `go` on PATH; not Go-lang-the-sibling — do not confuse it
with Rust, Swift or anything else, and check `go help` / the stdlib source in
`/usr/lib/go/src` when in doubt).

`culvert` resolves six **settings** from four layers, one setting at a time, and
prints them or audits them. Everything is graded by running your binary, and by
**rebuilding** it from your source with no network: the program may use **only
the standard library** (in particular the stdlib `flag` module is the only
command-line parsing you need), so any third-party dependency makes the verifier's
rebuild fail.

## Deliverables (create exactly these)

| path | what |
|---|---|
| `/app/culvert` | the compiled, executable binary of the CLI |
| `/app/culvert-src/main.go` | the CLI's source code |

Build contract: `/app/culvert-src/main.go` is the program's only source file and
must compile standalone with the single command

```
go build -o <out> /app/culvert-src/main.go
```

(no `go.mod`, no `go mod init`, no dependency resolution — the verifier issues
exactly this command, offline, to rebuild the binary from your source). Build
the delivered binary yourself with the same command. Do not modify
`/app/culvert.conf`; it is a fixture. Everything you create goes under `/app`.

## The settings (canonical order)

| # | setting | flag | env var | default | type | rules |
|---|---|---|---|---|---|---|
| 1 | `endpoint`  | `--endpoint`    | `CULVERT_ENDPOINT`    | `https://relay.example/sink` | string | non-empty, starts with `http://` or `https://`, no control characters |
| 2 | `region`    | `--region`       | `CULVERT_REGION`      | `us-east` | string | non-empty, no control characters |
| 3 | `timeout_ms`| `--timeout-ms`   | `CULVERT_TIMEOUT_MS`  | `15000`   | integer | 1000..600000 |
| 4 | `retries`   | `--retries`      | `CULVERT_RETRIES`     | `3`       | integer | 0..10 |
| 5 | `verbose`   | `--verbose`      | `CULVERT_VERBOSE`     | `false`   | bool    | `true`/`false` (any capitalization) |
| 6 | `max_batch` | `--max-batch`    | `CULVERT_MAX_BATCH`   | `500`     | integer | 1..100000 |

Integers are decimal, optionally with a single leading `-`. Booleans are
`true`/`false` compared case-insensitively. A string is a "value" only after the
leading/trailing whitespace described below has been removed; control characters
are bytes below 0x20 anywhere in the value.

## The four layers and the precedence rule

For **each setting individually**, the effective value is the first layer that
provides one, in this order:

1. **flag** — the setting's flag was given on the command line (e.g.
   `--timeout-ms=30000` or `--retries 4`; a `--verbose` given bare means
   `true`).
2. **env** — the setting's environment variable is **set** in the process
   environment (use a lookup that distinguishes unset from set-to-empty: a
   variable that is present with an empty value counts as *set* with the empty
   value).
3. **config** — the config file (below) defines the setting.
4. **default** — the table's default; defaults are always valid.

Values from the env and config layers are trimmed of leading/trailing spaces,
tabs and carriage returns before any parsing. A setting whose winning-layer
value is invalid (fails its type/range rules above) is a **usage error**
(exit code 2, see below); the first offending setting in canonical order is
reported.

Every retained value is used in its **canonical form**: integers are normalized
to their decimal text (e.g. `0008` → `8`), booleans are lowercased to
`true`/`false`, strings are the trimmed text.

## The config file

Default path `/app/culvert.conf`, overridable with the `--config PATH` flag.

- Plain text, one setting per line, `key = value`, key and value trimmed.
- Blank lines are ignored. Lines whose first non-whitespace character is `#`
  are comments and ignored. Inline `#` is part of the value.
- The key is everything up to the **first** `=`, the value everything after it.
  Unknown keys are ignored. A key repeated later in the file wins.
- A file that exists but cannot be read is treated as absent (all defaults).
- A line that is not a comment, not blank, and contains no `=` makes the whole
  file **malformed**: every subcommand must then print
  `culvert: config error: line <N>` (its 1-based line number) to **stderr** and
  exit with code **3**, writing nothing to stdout.

## Exit codes

| code | meaning |
|---|---|
| 0 | success: `resolve`; `diff` with no drift; `check` all valid |
| 1 | `diff` found drift; `check` found problems (the report is still fully printed on stdout) |
| 2 | usage error: missing or unknown subcommand; unknown flag or a flag value the stdlib parser rejects; `--format` not `json`/`table`; an invalid setting value in the winning layer; stray positional arguments |
| 3 | config file malformed |

Any exit-2 or exit-3 path writes its diagnostics **only to stderr** and **nothing
to stdout**. Diagnostic messages start with `culvert:`; the following fixed
templates are used: `culvert: missing subcommand (resolve|diff|check)`,
`culvert: unknown subcommand: <x>`, `culvert: unexpected argument: <x>`,
`culvert: invalid --format: <x>`, and for invalid setting values
`culvert: <setting> (<layer>): <error template>` where `<layer>` is
`flag`, `env`, or `config`, e.g. `culvert: timeout_ms (env): not an integer`.

## The subcommands

Every subcommand accepts **all** of the flags below, typed **after** the
subcommand name:

```
culvert <subcommand> [flags...]
```

| flag | meaning |
|---|---|
| `--format json\|table` | output mode, default `json` |
| `--config PATH` | config file, default `/app/culvert.conf` |
| `--endpoint`, `--region`, `--timeout-ms`, `--retries`, `--verbose`, `--max-batch` | the setting flags |

Unknown flags, and flags before the subcommand, are usage errors (exit 2).
`<subcommand>` must be exactly one of:

- **`resolve`** — prints the effective settings: all six, in canonical order,
  each with its winning-layer canonical value.
- **`diff`** — prints the "drift" report: exactly those settings whose effective
  value differs from what the config file alone would contribute (the file's
  canonical value when it defines the setting, otherwise the default). Each
  entry shows the setting, its effective value, and the source layer of the
  effective value (`flag`/`env`/`config`/`default`). Exit 0 when no setting
  drifts, 1 otherwise. (An invalid winning-layer value is still a usage error,
  exit 2, as in `resolve`.)
- **`check`** — audits **every layer independently**: for each setting in
  canonical order, validate the flag value (if the flag was given), the env
  value (if set — including set-to-empty), and the config value (if the file
  defines the setting). An invalid value that some other layer overrides is
  still reported. Problems are ordered by setting in canonical order, then by
  layer in the order `flag`, `env`, `config`. Exit 0 when there are none, 1
  otherwise. A malformed config file aborts with exit 3 before any per-key
  validation. The only error templates ever emitted are exactly:
  `not an integer`, `out of range`, `must be true or false`,
  `must not be empty`, `must start with http:// or https://`,
  `contains control characters`.

## Machine-readable output

Both modes write one line per record and end with a single trailing newline
(after the last record there is exactly one `\n`, and no other whitespace comes
after it).

**JSON mode** (`--format json`): no spaces, keys in the exact orders stated
above. String values are escaped exactly like the standard library's default
JSON encoder (`encoding/json`'s marshaler): `"`→`\"`, `\`→`\\`, `\t`→`\t`,
`\n`→`\n`, `<`→`\u003c`, `>`→`\u003e`, `&`→`\u0026`, other control bytes as
`\u00xx`; everything else passes through as UTF-8. Integers and booleans print
as their canonical text without quotes.

- `resolve`: `{"endpoint":S,"region":S,"timeout_ms":N,"retries":N,"verbose":B,"max_batch":N}`
- `diff`: `{"<setting>":{"value":V,"source":S},...}` over the drifting settings
  in canonical order, e.g. `{"region":{"value":"eu-west","source":"env"}}`;
  zero drift prints `{}`.
- `check`:
  `{"ok":true,"problems":[]}` or
  `{"ok":false,"problems":[{"setting":"timeout_ms","layer":"env","error":"not an integer"},...]}`.

**Table mode** (`--format table`): one row per line. Every column except the
last is padded with spaces on the right to the column's width, where a column's
width is the maximum width of any value in that column across the printed rows;
columns are separated by a single space; nothing follows the last column.

- `resolve`: six rows in canonical order — `<setting> <value>`, e.g.
  `timeout_ms  45000`.
- `diff`: rows in canonical order — `<setting> <value> <source>`; zero drift
  prints nothing at all.
- `check`: rows in problem order — `<setting> <layer> <error>`; with no problems
  the single line is exactly `all ok`.

## What to do

1. Read the Go stdlib sources under `/usr/lib/go/src` as needed (`flag`,
   `encoding/json`, `os`, `strconv`, `strings`, `fmt` are the packages this
   task is designed around; `go help` documents the toolchain).
2. Write `/app/culvert-src/main.go`, build `/app/culvert`, and check the
   behaviour yourself against the contract above: the visible fixture
   `/app/culvert.conf` and the default `--format json` should already produce
   sensible output, and you can mount your own test configs and env vars with
   `env CULVERT_...=... /app/culvert resolve --config <path>`.
3. Deliver both files. The verifier runs the shipped binary against the
   visible fixture and **rebuilds your source** to run four hidden
   config/env/flag combinations, asserting byte-exact output and exact exit
   codes. How the program is organized internally — helpers, data layout,
   comments — is entirely up to you; only the observable contract is graded.