# Lintkit: author three lint rules, extend suppression, add an incremental cache

This is a **linter rule engineering** task: you author static-analysis rules,
add suppression directives and an incremental results cache on top of an
existing mini lint engine.
Python-like subset, under `/app/lintkit/`:

- `lexer.py` — tokenizer (COMMENT tokens are kept; indentation is not encoded).
- `parser.py` — indentation-driven recursive-descent parser (`parse(text, file)`
  returns a `Module`).
- `ast_nodes.py` — tiny AST node types.
- `analyze.py` — structural annotations (`build_context`, `all_nodes`).
- `lint.py` — the CLI. **A working skeleton**: it loads rule plugins from
  `/app/rules/`, scans files, prints sorted findings JSON, and already honours
  the *line-scoped* suppression directive. You must extend it (see below).

A fixed configuration file `/app/rules/forbid_call.json` (JSON array of names)
is shipped; the rule plugin reads it (never hard-code the list differently,
and never edit the file). Visible examples live in `/app/examples/`.

## Deliverables (create/complete all of them)

1. `/app/rules/forbid_call.py` — rule plugin `forbid-call`
2. `/app/rules/shadow_var.py` — rule plugin `shadow-var`
3. `/app/rules/mut_default.py` — rule plugin `mut-default`
4. `/app/lintkit/lint.py` — extend the skeleton with region + next-statement
   suppression and the incremental cache (below)

## Rule plugin API

A rule module contributes one or more rule plugins. Each plugin is a class
with:

- `id` — non-empty `str`, the rule identifier;
- `description` — `str`;
- `check(self, node, ctx) -> list[dict]` — called once for every AST node in
  pre-order; returns finding dicts for that node:
  `{"id": str, "line": int, "col": int, "message": str}`.

`ctx` exposes `ctx.root` (the parsed+annotated `Module`), `ctx.file`,
`ctx.text` (raw source) and `ctx.rules_dir`. Return `[]` for nodes you do not
handle.

### minipy basics

Comments run from `#` to end of line. Blocks are indentation-based; compound
headers end with `:`. Statements: assignment `x = e` / augmented
`x += e` (also `-=`, `*=`, `/=`, `%=`), `def f(p, q=e, ...):`, `if/elif/else`,
`for v in e:`, `while e:`, `return e`, `pass`, `break`, `continue`, and
expression statements. Expressions: names, int/float/string literals,
`True/False/None`, lists `[...]`, dicts `{k: v, ...}` (empty `{}` is a dict),
sets `{a, b}`, calls `f(...)` / `a.b.c(...)`, attributes, binary ops
`+ - * / %` and `== != < > <= >=`, `and or not`. One statement per line
(no semicolons). Function definitions may nest.

### Node types (key ones)

`Module` (`.body`, `.text`, `.file`, `.stmt_start_lines`),
`FunctionDef` (`.name`, `.name_line`, `.name_col`, `.params`, `.body`),
`Param` (`.name`, `.default`, `.line`, `.col`), `Assign`/`AugAssign`
(`.target`, `.value`), `For` (`.target`, `.iter`, `.body`), `While`,
`If` (`.test`, `.body`, `.elifs`, `.orelse`), `Return`, `Pass`, `Break`,
`Continue`, `ExprStmt` (`.value`), `Call` (`.func`, `.args`, `.name`,
`.is_attr`, `.name_line`, `.name_col`, plus `.func_depth` after
`build_context`), `Attribute`, `Name` (`.id`), `List`, `Dict`, `Set`, `Int`,
`Float`, `Str`, `Bool`, `NoneLit`, `BinOp`, `BoolOp`, `Compare`, `UnaryOp`.
`analyze.all_nodes(root)` yields every node pre-order.

## Rule semantics (exact)

### forbid-call (id `forbid-call`)
- Forbidden names come from `<rules_dir>/forbid_call.json` (fixed shipped
  list: `eval`, `exec`, `shell`, `system`, `popen`, `network_open`,
  `send_wire`).
- A `Call` is flagged when its **final callee name** is forbidden — direct
  form `name(...)` and attribute form `obj.name(...)` / `a.b.name(...)` alike.
- Scope rule: only calls that occur **inside a function body** are flagged
  (`node.func_depth >= 1`). Top-level calls are never flagged. Calls in a
  function's parameter defaults sit at the depth of the surrounding code
  (not the new body).
- Anchor: the callee-name token (`Call.name_line`, `Call.name_col`).
- Message: `forbidden call to <name>`.

### shadow-var (id `shadow-var`)
Block model (fixed): the module is the root scope; every compound statement
(`if` / `elif` / `else` / `for` / `while` / `def`) introduces a child scope
holding its suite; a name is bound in the scope that directly contains its
binding statement. Bindings come from assignment targets, for-loop targets
(the scope containing the `for`), function parameters (bound in the new
function scope) and definition names of nested `def`s.

`build_context(root)` builds `root.scope_tree` (a `Scope` with `.parent`,
`.children`, `.names` = names bound directly, `.bindings` = list of
`(name, node, kind)` where `kind` is `assign`, `for`, `param` or `def`), and
tags each binding node with `._scope` and `._kind`.

A binding of name `n` in scope `S` **shadows** when `n` is already bound in
any strict ancestor scope of `S`; redefining `n` inside the same scope is not
a shadow, and sibling scopes never shadow each other.

- Anchor: the binding's name token — for a `def` binding use
  `FunctionDef.name_line/name_col`, otherwise the node's `line/col`.
- Message: `shadowing of <name>`.
- Emit exactly one finding per shadowing binding.

### mut-default (id `mut-default`)
- For every `FunctionDef`, flag each parameter whose default value is a
  **mutable literal**: a `List`, a `Dict` (including empty `{}`) or a `Set`.
  Defaults that are names, calls, numbers, strings, booleans or `None` are
  not flagged.
- Anchor: the parameter name token (`Param.line`, `Param.col`).
- Message: `mutable default for <name>`.

## Suppression directives (implement in lint.py)

A comment is a directive when its text after `#` (trimmed) matches one of:

| form | syntax | effect |
|------|--------|--------|
| line | `# nolint(<ids>)` | suppress `<ids>` on the comment's own line |
| region | `# nolint-begin(<ids>)` ... `# nolint-end(<ids>)` | suppress `<ids>` on every line from begin through end (inclusive); nesting is matched with a stack per id; an unclosed begin extends to the last source line |
| next | `# nolint:next(<ids>)` | suppress `<ids>` on the single line equal to the next statement's start line strictly after the directive |

`<ids>` is a comma-separated list of rule ids. A finding is suppressed when
**any** applicable directive (line, region or next, for its id) hides its
anchor line; there is no re-enabling. Statement start lines are available as
`Module.stmt_start_lines`.

## Incremental findings cache (implement in lint.py)

- Cache directory `/app/lintcache` (override with `--cache-dir`).
- Cache key per input file: `sha256("\n".join(sorted(rule ids)))` + `_` +
  `sha256(file bytes)` + `.json` (a single JSON file holding the file's
  sorted finding array).
- On a run: if the key file exists, reuse it (cache hit — do not re-run the
  rules); otherwise compute findings, write the entry (cache miss). Findings
  JSON must be byte-identical (JSON-identical) whether reused or recomputed.
- `--stats` prints exactly these lines to **stderr**:
  `cache:dir=...`, `cache:inputs=N`, `cache:hits=N`, `cache:misses=N`,
  `cache:reused=path1,path2`, `cache:computed=path3` (paths in input order).
- `--no-cache` disables both reading and writing.

## CLI contract

`python3 /app/lintkit/lint.py [--stats] [--no-cache] [--cache-dir DIR] [--rules-dir DIR] FILE...`

- stdout: a single JSON object mapping each input path (exactly as given) to
  its finding array, each sorted by `(line, col, id, message)`. Files with no
  findings produce `[]`. Exit code `0` on success.
- Rules are loaded from `/app/rules/`; a malformed rule must not abort the run.

## How the grader probes your work

Hidden minipy sources (under `/tests/hidden`, various nesting depths, chained
and overlapping suppressions, cache-hit/invalidation scenarios) are run
through `/app/lintkit/lint.py`. The verifier independently recomputes the
expected findings — its own private implementation of the three rules and the
suppression semantics — and compares the exact JSON. It also runs the CLI
twice against a fresh `/app/lintcache` and checks `--stats` reports hits on
the second pass, then mutates a copy of a hidden file and requires a cache
miss with updated findings. Hard-coding the visible examples cannot pass:
hidden sources exercise different shapes, and the reference is recomputed
from the specified semantics.

## Constraints

- Python standard library only; no network access; keep everything
  deterministic. Do not modify `/app/lintkit/lexer.py`, `parser.py`,
  `ast_nodes.py` or `analyze.py` — treat them as fixed infrastructure.
- `python3` is available at `/usr/bin/python3` (3.12).