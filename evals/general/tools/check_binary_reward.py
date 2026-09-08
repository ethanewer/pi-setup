#!/usr/bin/env python3
"""Reward binarity gate.

The suite contract is that every verifier writes /logs/verifier/reward.txt as
exactly 1.0 (full credit) or 0.0 (anything less). WORKFLOW.md has always said
so, but no gate enforced it, so 44 tasks shipped partial-credit verifiers and
the published "pass_rate" numbers were really mean reward.

This gate proves binarity statically. For each task it builds the reward value
cone: every expression whose value can reach reward.txt.

  1. seed with the expressions written to reward.txt
     (shell `echo/printf ... > reward.txt`, `cmd > reward.txt`,
      python `open(...).write(EXPR)`, `with open(...) as fh: fh.write(EXPR)`)
  2. for each identifier in a seed, pull in every assignment to it
     (`NAME = ...`, `NAME += ...`, python `D['NAME'] = ...`, `obj.NAME = ...`)
  3. when an assignment's right side is a command substitution or heredoc,
     recurse into that body using its top-level print(...) calls as seeds
  4. repeat to a fixed point

Then it flags any cone expression that can yield a value other than 0 or 1:
a fractional literal, a division, fractional formatting, round(x, n>=1), a
weighted term, a bc/scale fractional computation, a clamp around a continuous
value, or a bare integer outside {0, 1} written straight to reward.txt.

Exit 0 when every task is provably binary. Use --json for a machine-readable
report and --task NAME to inspect one task's cone.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'

REWARD_PATH = re.compile(r'reward\.txt')

# `REWARD_FILE=/logs/verifier/reward.txt` and friends: the path lives in a
# variable, so writes redirect to "$REWARD_FILE" and never mention reward.txt.
PATH_VAR = re.compile(
    r'(?:^|[;\s])([A-Za-z_]\w*)\s*=\s*["\']?[^\n"\']*reward\.txt|'
    r'\b([A-Za-z_]\w*)\s*=\s*["\'][^"\']*reward\.txt["\']')


def reward_target_alts(srcs):
    """Return (line_filter, target_alternation) for a task's sources.

    `target_alternation` matches the redirect destination only, so write
    detection works inside one-liners like
    `fail() { echo "$*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }`.
    """
    names = set()
    for src in srcs:
        for line in src.splitlines():
            for m in PATH_VAR.finditer(line):
                nm = m.group(1) or m.group(2)
                if nm and nm not in ('LOGS', 'V', 'REWDIR'):
                    names.add(nm)
    parts = [r'\S*reward\.txt']
    for nm in sorted(names):
        parts.append(rf'["\']?\$\{{?{re.escape(nm)}\}}?["\']?')
    return None, '(?:' + '|'.join(parts) + ')'

# identifiers that are never reward values. `reward`/`REWARD`/`score` are the
# usual reward variable names and must stay trackable, so they are not listed.
NOISE = {
    'echo', 'printf', 'str', 'repr', 'int', 'float', 'bool', 'write', 'open',
    'print', 'format', 'f', 'fh', 'fout', 'out', 'w', 'n', 's', 'logs',
    'verifier', 'txt', 'logs_verifier', 'if', 'else', 'elif', 'then',
    'fi', 'exit', 'cat', 'dev', 'null', 'true', 'false', 'and', 'or', 'not',
    'in', 'is', 'for', 'while', 'return', 'def', 'class', 'import', 'from',
    'as', 'with', 'try', 'except', 'finally', 'pass', 'break', 'continue',
    'len', 'sum', 'min', 'max', 'abs', 'round', 'any', 'all', 'sorted',
    'self', 'cls', 'None', 'NoneType', 'sys', 'os', 'json', 'math', 're',
}

BINARY_LITERALS = {'0', '1', '0.0', '1.0', '0.00', '1.00', '00', '01'}

# reasons an expression can produce a non-binary reward
CHECKS = [
    ('fractional-literal',
     re.compile(r'(?<![\w.])(\d+\.\d+|\.\d+)(?![\w.])')),
    ('division',
     re.compile(r'(?<=[\w\)\]])\s*/\s*(?=[\w\(\$])')),
    ('fractional-format',
     re.compile(r'[%:]\.\d+f')),
    ('round-decimals',
     re.compile(r'\bround\s*\([^()]*,\s*[1-9]\d*\s*\)')),
    ('weighted-term',
     re.compile(r'\*\s*0\.\d+|0\.\d+\s*\*')),
    ('bc-fractional',
     re.compile(r'\bbc\s+-l\b|\bscale\s*=\s*[1-9]')),
    ('continuous-clamp',
     re.compile(r'\bmin\s*\([^()]*,\s*1(?:\.0+)?\s*\)|\bmax\s*\([^()]*,\s*0(?:\.0+)?\s*,')),
]

# path prefixes that make a `/` a filesystem path, not a division
PATH_WORDS = ('app', 'logs', 'tmp', 'tests', 'workspace', 'usr', 'dev', 'etc',
              'var', 'opt', 'home', 'root', 'proc', 'sys', 'mnt', 'data', 'srv',
              'run', 'bin', 'lib', 'snap', 'media', 'net', 'tests/hidden')


def clean(line: str) -> str:
    """Strip comments and things that look like division but are not."""
    line = strip_shell_comment(line)
    line = re.sub(r'https?://\S+', ' ', line)
    line = re.sub(r'\{\s*(?:print|printf)\s+\$\d+\s*\}', ' ', line)
    line = re.sub(r'\b cut\b[^|]*', ' ', line)
    return line


def strip_shell_comment(line: str) -> str:
    """Drop a trailing # comment that is not inside a quoted string.

    Without this, `reward=0   # ABI ok but runner/emission failing` reads as a
    division because of the slash in the comment.
    """
    out, quote, i = '', None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            out += ch
            if ch == '\\' and i + 1 < len(line):
                out += line[i + 1]
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
            out += ch
        elif ch == '#':
            break
        else:
            out += ch
        i += 1
    return out.rstrip()


def strip_paths(line: str) -> str:
    for w in PATH_WORDS:
        line = re.sub(rf'(?<![\w.])/{w}\b[\w./\-]*', ' ', line)
    # drop quoted strings that are plainly filesystem paths. Only path-shaped
    # ones: blanking every quoted string with a slash erased real evidence
    # such as "print(round($points/100.0, 4))".
    def is_path(m):
        body = m.group(0)[1:-1]
        return body.startswith('/') and ' ' not in body and not re.search(r'[%:]', body)
    line = re.sub(r'"[^"\n]*"', lambda m: ' ' if is_path(m) else m.group(0), line)
    return line


# ---------------------------------------------------------------- sources

def heredoc_bodies(text: str):
    """Yield (start_index, body) for every heredoc in text."""
    for a, b, body in heredoc_spans(text):
        yield a, body


def heredoc_spans(text: str):
    """Yield (body_start, body_end, body) for every heredoc in text."""
    for m in re.finditer(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", text):
        nl = text.find('\n', m.end())
        if nl < 0:
            continue
        end = re.search(rf'^\s*{re.escape(m.group(1))}\s*$', text[nl + 1:], re.M)
        if end:
            start = nl + 1
            stop = start + end.start()
            yield start, stop, text[start:stop]


def blank_heredocs(text: str) -> str:
    """test.sh with every heredoc body blanked, preserving length and offsets.

    Shell and embedded python are different scopes. A heredoc that computes
    `reward = passes / total` for python has nothing to do with the shell
    variable of the same name that captures the heredoc's stdout, and treating
    them as one variable made this gate walk straight into the fractional
    internals of verifiers that were already binarized.

    Offsets are preserved exactly (non-newline characters become spaces) so a
    match found in the blanked text can be re-read from the original to recover
    the body of `VAR=$(python3 - <<'PY' ... PY)`.
    """
    out, last = [], 0
    for start, stop, body in heredoc_spans(text):
        if start < last:
            continue
        out.append(text[last:start])
        out.append(''.join('\n' if ch == '\n' else ' ' for ch in body))
        last = stop
    out.append(text[last:])
    return ''.join(out)


def subst_body(text: str, start: int) -> str:
    """Body of the $( ... ) whose `$` is at `start`."""
    if text[start:start + 2] != '$(':
        return ''
    depth, i = 1, start + 2
    while i < len(text):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return text[start + 2:i]
        i += 1
    return ''


def verifier_text(taskdir: Path) -> str | None:
    ts = taskdir / 'tests' / 'test.sh'
    if not ts.exists():
        return None
    return ts.read_text(errors='replace')


def helper_sources(taskdir: Path):
    """tests/*.py and tests/*.sh that the verifier can run."""
    out = {}
    for p in sorted((taskdir / 'tests').rglob('*')):
        if p.is_file() and p.suffix in ('.py', '.sh') and p.name != 'test.sh':
            out[str(p.relative_to(taskdir))] = p.read_text(errors='replace')
    return out


# ---------------------------------------------------------------- cone

PY_OPEN = re.compile(r'open\(\s*[^\n)]*reward\.txt[^\n)]*\)\s*\.write\(\s*(?P<val>[^\n)]*)')
WITH_OPEN = re.compile(r'with\s+open\([^)]*reward\.txt[^)]*\)\s+as\s+(\w+)\s*:')


def py_seeds_from_body(body: str):
    """Top-level print(...) args in a python body: what becomes stdout.

    The argument is extracted by matching parentheses rather than by taking the
    rest of the line. A verifier that writes

        print('recovered db missing'); raise SystemExit(1)

    puts that message on stdout, and when the shell captures the interpreter's
    stdout into the reward the message becomes the reward. Taking the remainder of
    the line yielded the compound string `'recovered db missing'); raise
    SystemExit(1`, which no classifier recognised, so the defect passed the gate
    and shipped.
    """
    seeds = []
    for line in body.splitlines():
        s = line.strip()
        if s.startswith('#'):
            continue
        for m in re.finditer(r'\bprint\s*\(', s):
            i = m.end()
            depth = 1
            quote = None
            j = i
            while j < len(s):
                ch = s[j]
                if quote:
                    if ch == '\\':
                        j += 2
                        continue
                    if ch == quote:
                        quote = None
                elif ch in '"\'':
                    quote = ch
                elif ch in '([':
                    depth += 1
                elif ch in ')]':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            seeds.append(s[i:j])
    return seeds


ASSIGN_SHELL = re.compile(r'(?:^|[;(\s]|\blocal\s+|\bexport\s+|\breadonly\s+)'
                          r'(?P<name>[A-Za-z_]\w*)\s*=(?!=)')
ASSIGN_PY = re.compile(r'(?P<name>[A-Za-z_]\w*)\s*(?:\+|-|\*|/|//)?=(?!=)')
SUBSCRIPT_ASSIGN = re.compile(r'[A-Za-z_]\w*\[\s*[\'"](?P<key>[A-Za-z_]\w*)[\'"]\s*\]\s*(?:\+?=)(?!=)')
ATTR_ASSIGN = re.compile(r'[A-Za-z_]\w*\.(?P<key>[A-Za-z_]\w*)\s*(?:\+?=)(?!=)')


def assignments_to(srcs, name, raw=None):
    """Every value assigned to `name`, plus bodies whose stdout it captures.

    `srcs` is what values are read from; `raw` is an offset-identical copy used
    to recover command-substitution bodies. They differ when `srcs` has heredocs
    blanked so shell lookup cannot see python locals, while the body of
    `VAR=$(python3 - <<'PY' ... PY)` still has to be read from the original.

    A body is attached only when the assigned value really is a command
    substitution. `python3 - <<'PY' && REWARD=1` runs the heredoc for its exit
    code, so REWARD is the literal 1 and the heredoc's stdout (which may contain
    diagnostic %.4f formatting) never reaches reward.txt.

    A single shell line can hold several branches (`[ "$ok" -eq 1 ] && reward=1
    || reward=0`), so each fragment is captured separately.
    """
    rhs_list, bodies = [], []
    esc = re.escape(name)
    pats = [
        re.compile(rf'(?:^|[;(\s]|\blocal\s+|\bexport\s+|\breadonly\s+){esc}\s*=(?!=)\s*([^\n]*)', re.M),
        re.compile(rf'(?:^|[;(\s]){esc}\s*(?:\+|-|\*|/|//)=(?!=)\s*([^\n]*)', re.M),
        re.compile(rf'[A-Za-z_]\w*\[\s*[\'"]{esc}[\'"]\s*\]\s*(?:\+?=)(?!=)\s*([^\n]*)', re.M),
        re.compile(rf'[A-Za-z_]\w*\.{esc}\s*(?:\+?=)(?!=)\s*([^\n]*)', re.M),
    ]
    pairs = list(zip(srcs, raw)) if raw else [(s, s) for s in srcs]
    for src, rawsrc in pairs:
        for pat in pats:
            for m in pat.finditer(src):
                rhs_at = m.start(1)
                # the match can begin on the preceding newline, so take the line
                # that actually holds the assignment, not the one before it
                line_start = src.rfind('\n', 0, rhs_at) + 1
                if src[line_start:rhs_at].lstrip().startswith('#'):
                    continue
                first_line = src[rhs_at:].split('\n', 1)[0]
                stripped = first_line.lstrip()
                if stripped.startswith('$('):
                    # VAR=$( ... ) : the substitution's stdout is the value
                    dollar = rawsrc.index('$(', rhs_at)
                    b = subst_body(rawsrc, dollar)
                    if b:
                        bodies.append(b)
                    rhs_list.append(first_line.strip())
                    continue
                for frag in re.split(r'\s*(?:;|\|\||&&)\s*', first_line):
                    frag = frag.strip()
                    if not frag:
                        continue
                    rhs_list.append(frag)
                    if '$(' in frag:
                        d = frag.index('$(')
                        b = subst_body(frag, d)
                        if b:
                            bodies.append(b)
    return rhs_list, bodies


def call_arg(src: str, open_paren: int) -> str:
    """Balanced argument of the call whose `(` is at `open_paren`.

    `[^)]*` truncates `.write("1" if (r) >= 1.0 else "0")` to `"1" if (r`,
    which then no longer looks like the binary ternary it is.
    """
    depth, i = 0, open_paren
    while i < len(src):
        ch = src[i]
        if ch in '\'"':
            q = ch
            i += 1
            while i < len(src) and src[i] != q:
                i += 2 if src[i] == '\\' else 1
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return src[open_paren + 1:i]
        i += 1
    return src[open_paren + 1:].split('\n', 1)[0]


def write_args(src: str):
    """Every argument written to reward.txt (or to an already-open handle)."""
    out = []
    for m in re.finditer(r'\.write\(', src):
        head = src[max(0, m.start() - 300):m.start()]
        if 'reward.txt' in head or re.search(r'as\s+(?:fh|f|fout|out)\s*:\s*$', head):
            out.append(call_arg(src, m.end() - 1))
    return [o.strip() for o in out if o.strip()]


def py_write_seeds(src: str, origin: str):
    """Scalar expressions a python source writes into reward.txt.

    Covers `open("...reward.txt", "w").write(E)`, `with open(...) as fh:
    fh.write(E)`, a constant holding the path (`REWARD = "...reward.txt"` then
    `open(REWARD, "w").write(E)`), and a helper function that writes the file
    (`def write(r): ...` called as `write(reward)`).
    """
    out = []
    for val in write_args(src):
        out.append((f'{origin}:py-write', val))
    consts = {(m.group(1) or m.group(2)) for m in PATH_VAR.finditer(src)
              if (m.group(1) or m.group(2))}
    for nm in sorted(consts):
        e = re.escape(nm)
        for w in re.finditer(rf'open\(\s*{e}\s*,\s*["\']w["\']\s*\)\s*\.write\(', src):
            out.append((f'{origin}:py-write-const', call_arg(src, w.end() - 1)))
        for w in re.finditer(rf'with\s+open\(\s*{e}[^)]*\)\s+as\s+(\w+)', src):
            tail = src[w.end():w.end() + 1500]
            for x in re.finditer(rf'\b{re.escape(w.group(1))}\.write\(', tail):
                out.append((f'{origin}:py-write-const', call_arg(tail, x.end() - 1)))
                break
        for w in re.finditer(rf'\b{e}\b[^\n]*?\.write_text\(', src):
            out.append((f'{origin}:py-write-const', call_arg(src, w.end() - 1)))
    for arg in reward_fn_calls(src, consts):
        out.append((f'{origin}:write-call', arg))
    return out


REWARD_FN = re.compile(r'def\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*:')


def reward_fn_calls(src: str, path_consts=()):
    """Seed expressions for helpers like `def write(r): open(...reward.txt...).write(r)`.

    Returns the argument expression of every call to a function whose body writes
    reward.txt, so `reward = 0.5; write(reward)` puts `reward` in the cone. The
    body may write the literal path or a constant that holds it.
    """
    seeds = []
    lines = src.splitlines()
    writers = set()
    const_re = re.compile(r'\b(?:' + '|'.join(re.escape(c) for c in path_consts) + r')\b') if path_consts else None
    for i, line in enumerate(lines):
        m = REWARD_FN.match(line.strip())
        if not m:
            continue
        fname = m.group(1)
        indent = len(line) - len(line.lstrip())
        body = []
        for nxt in lines[i + 1:]:
            if not nxt.strip():
                continue
            if (len(nxt) - len(nxt.lstrip())) <= indent:
                break
            body.append(nxt)
        joined = '\n'.join(body)
        if 'reward.txt' in joined or (const_re and const_re.search(joined) and '.write' in joined):
            # if the helper already binarizes what it writes, no value a caller
            # passes can make the reward fractional, so do not seed the call
            own = write_args(joined)
            if own and all(self_contained_binary(a) or a.strip('"\'') in BINARY_LITERALS
                           for a in own):
                continue
            writers.add(fname)
    for fname in writers:
        for m in re.finditer(rf'(?<![\w.]){re.escape(fname)}\s*\(([^\n)]*)\)', src):
            if m.group(1).strip():
                seeds.append(m.group(1).strip())
    return seeds


def identifiers(expr: str):
    names = set(re.findall(r'\$\{?([A-Za-z_]\w*)\}?', expr))
    names |= set(re.findall(r'\b([A-Za-z_]\w*)\b', expr))
    names |= set(re.findall(r'\[\s*[\'"]([A-Za-z_]\w*)[\'"]\s*\]', expr))
    return {n for n in names if n not in NOISE and not n.isdigit()}


def build_cone(taskdir: Path, trace=False):
    """Return the list of (origin, expression) whose value can reach reward.txt.

    Two kinds of source feed a reward:

      * a scalar expression written straight to the file (`echo "$reward" > ...`,
        `open(...).write(EXPR)`, `write(reward)` through a helper that writes it)
      * the stdout of a command whose output is captured into the reward, either
        by redirection (`python3 -c "..." > reward.txt`) or by substitution
        (`score=$(python3 - <<'PY' ... PY)`)

    Only those two are followed. A helper run for its exit code
    (`python3 /tests/check.py || reward=0`) contributes nothing, because its
    stdout never becomes the reward.

    Shell and embedded python are audited in separate scopes (see blank_heredocs),
    so a python local named `reward` is never confused with the shell variable
    that captures the interpreter's stdout.
    """
    text = verifier_text(taskdir)
    if text is None:
        return None, ['no tests/test.sh']
    helpers = helper_sources(taskdir)
    sh_helpers = [(k, v) for k, v in helpers.items() if k.endswith('.sh')]
    py_helpers = [(k, v) for k, v in helpers.items() if k.endswith('.py')]
    heredocs = [b for _, b in heredoc_bodies(text)]
    all_texts = [text] + [v for _, v in helpers.items()]

    notes = []
    if not any(REWARD_PATH.search(v) for v in all_texts):
        return [], ['verifier never writes reward.txt']
    _, TARGET = reward_target_alts(all_texts)
    tgt = re.compile(r'reward\.txt|' + TARGET)
    mw_re = re.compile(rf'(?:echo|printf)\s+(?:["\']?%[sdfg]["\']?\s+)*([^>;]*?)\s*>>?\s*{TARGET}')
    md_re = re.compile(rf'(.*?)\s*>>?\s*{TARGET}')

    shell_text = blank_heredocs(text)
    sh_helper_vals = [v for _, v in sh_helpers]
    # (values, offset-identical originals) so a substitution body blanked out of
    # the shell view can still be recovered from the real text
    shell_scope = (tuple([shell_text] + sh_helper_vals),
                   tuple([text] + sh_helper_vals))

    cone = []
    seen = set()
    scalar_q = []      # (origin, expression, scope_sources)
    stdout_q = []      # (origin, body, scope_sources)

    def add_scalar(origin, expr, srcs):
        expr = (expr or '').strip()
        if not expr:
            return
        key = (expr[:250], id(srcs))
        if key not in seen:
            seen.add(key)
            scalar_q.append((origin, expr, srcs))

    def add_stdout(origin, body, srcs=None):
        body = (body or '').strip()
        if not body:
            return
        srcs = ((body,), (body,)) if srcs is None else srcs
        key = ('BODY:' + body[:250], id(srcs))
        if key not in seen:
            seen.add(key)
            stdout_q.append((origin, body, srcs))

    def expand_var(name, scope):
        vals, raws = scope
        rhs_list, bodies = assignments_to(list(vals), name, raw=list(raws))
        for rhs in rhs_list:
            add_scalar(f'var:{name}', rhs, scope)
        for b in bodies:
            add_stdout(f'var:{name}:subst', b)

    # ---- 1. shell writes, and shell commands redirected into reward.txt ---
    for name, src in [('test.sh', shell_text)] + sh_helpers:
        for line in src.splitlines():
            s = line.strip()
            if s.startswith('#') or not tgt.search(s):
                continue
            hits = list(mw_re.finditer(s))
            for mw in hits:
                if mw.group(1).strip():
                    add_scalar(f'{name}:sh-write', mw.group(1), shell_scope)
            if hits:
                continue
            for md in md_re.finditer(s):
                cmd = md.group(1).strip().lstrip(';{ ')
                if cmd and not cmd.startswith(('rm', 'mkdir', 'touch', '[', 'test',
                                               'if', 'dirname', 'cat /dev/null')):
                    add_stdout(f'{name}:redirect', cmd)

    # ---- 2. python scopes that write reward.txt themselves ---------------
    py_scopes = [(f'heredoc{i}', hb) for i, hb in enumerate(heredocs)] + py_helpers
    for name, src in py_scopes:
        if not (REWARD_PATH.search(src) or tgt.search(src)):
            continue
        scope = ((src,), (src,))
        for origin, val in py_write_seeds(src, name):
            add_scalar(origin, val, scope)

    # ---- 3. walk to a fixed point ----------------------------------------
    for origin, expr, srcs in list(scalar_q):
        if self_contained_binary(expr):
            continue
        for nm in identifiers(expr):
            expand_var(nm, srcs)

    budget = 8000
    while (scalar_q or stdout_q) and budget > 0:
        budget -= 1
        if stdout_q:
            origin, body, _ = stdout_q.pop(0)
            inline = re.search(r'python3?\s+-c\s+(["\'])(.*?)\1\s*$', body, re.S)
            sub = inline.group(2) if inline else body
            scope = ((sub,), (sub,))
            awkm = re.search(r'awk\s+["\']?\s*(?:BEGIN\s*)?\{(.*)\}\s*["\']?\s*$', body, re.S)
            if awkm and not inline:
                prog = awkm.group(1)
                ascope = ((prog,), (prog,))
                for pm in re.finditer(r'\bprintf?\s+(.*)', prog):
                    expr = pm.group(1).strip()
                    add_scalar(f'{origin}:awk-print', expr, ascope)
                    if not self_contained_binary(expr):
                        for nm in identifiers(expr):
                            expand_var(nm, shell_scope)
                continue
            prints = py_seeds_from_body(sub)
            for ps in prints:
                add_scalar(f'{origin}:print', ps, scope)
            for ps in prints:
                # a print whose value is provably 0/1 needs no further walking;
                # its condition may legitimately test a fractional accumulator
                if self_contained_binary(ps):
                    continue
                for nm in identifiers(ps):
                    expand_var(nm, scope)
            for _, hb in heredoc_bodies(sub):
                hscope = ((hb,), (hb,))
                hprints = py_seeds_from_body(hb)
                for ps in hprints:
                    add_scalar(f'{origin}:heredoc-print', ps, hscope)
                for ps in hprints:
                    if self_contained_binary(ps):
                        continue
                    for nm in identifiers(ps):
                        expand_var(nm, hscope)
            if not prints:
                for m in re.finditer(r'(?:echo|printf)\s+([^\n>|]+)', body):
                    add_scalar(f'{origin}:echo', m.group(1), shell_scope)
            continue
        origin, expr, srcs = scalar_q.pop(0)
        cone.append((origin, expr))
        if self_contained_binary(expr):
            continue
        if expr.lstrip().startswith('$('):
            # the value is the command's stdout, already queued as a body; its
            # interpolated shell variables are condition inputs, not the value
            continue
        for nm in identifiers(expr):
            expand_var(nm, srcs)

    if budget <= 0:
        notes.append('cone expansion hit the budget; result may be partial')
    return cone, notes


BINARY_IDIOMS = [
    re.compile(r'^["\']?[01](?:\.0+)?["\']?$'),
    re.compile(r'^(?:["\']?[01](?:\.0+)?["\']?)\s+if\s+.+\s+else\s+(?:["\']?[01](?:\.0+)?["\']?)$'),
    re.compile(r'^int\(\s*[^()]*\)$'),
    re.compile(r'^\$\(\(\s*.*[<>=!]=.*\s*\)\)$'),
    re.compile(r'^(?:str|repr)\(\s*[A-Za-z_]\w*\s*\)$'),
    re.compile(r'^["\']?[01](?:\.0+)?\\n["\']?$'),
    re.compile(r'^%d(?:\\n)?["\']?\s*%\s*[A-Za-z_]\w*$'),
]

# Expressions that are 0 or 1 no matter what they contain, so the cone does not
# need to look inside them. `1 if (points/100.0) >= 1.0 else 0` is binary even
# though `points` is a weighted accumulator; expanding it anyway is what made
# this gate keep flagging tasks that were already fixed.
SELF_CONTAINED_BINARY = [
    re.compile(r'^(?:["\']?[01](?:\.0+)?["\']?)$'),
    re.compile(r'^(?:["\']?[01](?:\.0+)?["\']?)\s+if\s+.+\s+else\s+(?:["\']?[01](?:\.0+)?["\']?)$'),
    re.compile(r'^\(?[^()]*\)?\s*\?\s*1\s*:\s*0$'),            # awk  (cond)?1:0
    re.compile(r'^.+\?\s*1\s*:\s*0$'),                          # awk  ((a+b)>=4)?1:0
    re.compile(r'^\$\(\(\s*.*[<>=!]=.*\s*\)\)$'),               # shell arithmetic compare
]


def strip_print_kwargs(expr: str) -> str:
    """Drop trailing print() keyword args so `..., end=""` does not hide a ternary."""
    e = expr.strip()
    e = re.sub(r',\s*(?:end|sep|file|flush)\s*=.*$', '', e).strip()
    return e


def self_contained_binary(expr: str) -> bool:
    e = strip_print_kwargs(expr).strip()
    return any(rx.fullmatch(e) for rx in SELF_CONTAINED_BINARY)


def proven_binary(expr: str) -> bool:
    """True when this expression can only ever be 0 or 1."""
    e = strip_print_kwargs(expr).strip()
    if not e:
        return False
    if e.strip('"\'') in BINARY_LITERALS:
        return True
    if self_contained_binary(e):
        return True
    if any(rx.fullmatch(e) for rx in BINARY_IDIOMS):
        # a bare str(reward)/repr(r) is only as binary as the var behind it,
        # which the cone already expanded, so accept it here
        return True
    return False


def classify_expr(expr: str):
    """Return (is_non_binary, reason) for one cone expression."""
    e = expr.strip()
    if not e:
        return False, ''
    bare = e.strip('"\'')
    if bare in BINARY_LITERALS:
        return False, ''
    # A quoted literal that does not denote 0 or 1 is prose, and prose printed to
    # a captured stdout becomes the reward. '0.0' and '1.0' are value-binary even
    # though the publish step canonicalises their spelling, so judge by float.
    # Anything carrying a shell expansion is a variable reference rather than a
    # literal -- "$reward" is exactly what a correct verifier writes -- and is left
    # to the rest of the cone, which resolves the variable.
    if (len(e) >= 2 and e[0] == e[-1] and e[0] in '"\'' and e.count(e[0]) == 2
            and '$' not in e and '`' not in e):
        # Evaluate the literal rather than stripping quotes, so an escaped sequence
        # is read the way the interpreter reads it: '0\n' is the string "0\n",
        # which float() accepts, not the four characters that would look like prose.
        try:
            import ast as _ast
            val = _ast.literal_eval(e)
        except Exception:
            val = bare
        if isinstance(val, str):
            # A filesystem path is not a reward candidate. strip_paths already
            # blanks these for the arithmetic checks below; apply the same test
            # here so '/app/evidence' in a cone is not read as prose. The real
            # defect this catches -- 'recovered db missing' -- has spaces and so
            # survives, which is the distinction strip_paths was written for.
            if val.startswith('/') and ' ' not in val and not re.search(r'[%:]', val):
                pass
            else:
                try:
                    if float(val) not in (0.0, 1.0):
                        return True, f'non-binary literal reward {e[:80]}'
                except ValueError:
                    return True, f'prose literal written as reward: {e[:80]}'
    # a bare integer written straight to reward.txt that is not 0 or 1
    if re.fullmatch(r'-?\d+', bare) and int(bare) not in (0, 1):
        return True, f'bare integer reward {bare}'
    c = clean(e)
    c = strip_paths(c)
    # 0/1-producing idioms are fine even when they mention numbers
    if re.fullmatch(r'(?:1|0)\s+if\s+.+\s+else\s+(?:0|1)', c) or \
       re.fullmatch(r'int\(\s*.+\s*\)', c) or \
       re.fullmatch(r'\$\(\(\s*.+\s*\)\)', c) or \
       re.fullmatch(r'["\']?[01](?:\.0+)?["\']?\s+if\s+.+\s+else\s+["\']?[01](?:\.0+)?["\']?', c):
        return False, ''
    for why, rx in CHECKS:
        m = rx.search(c)
        if not m:
            continue
        if why == 'fractional-literal':
            tok = m.group(1)
            try:
                if float(tok) in (0.0, 1.0):
                    continue
            except ValueError:
                continue
            # scientific-notation tolerances are comparisons, not rewards
            if re.search(rf'{re.escape(tok)}\s*e', c):
                continue
        if why == 'division':
            frag = c[max(0, m.start() - 30):m.end() + 30]
            if re.search(r'\{\s*print\s+\$\d+\s*\}', frag) or '://' in frag:
                continue
            # a slash inside a quoted string is a path or prose, not arithmetic
            before = c[:m.start()]
            if before.count('"') % 2 == 1 or before.count("'") % 2 == 1:
                continue
        return True, f'{why}: {e[:110]}'
    return False, ''


def audit_task(taskdir: Path):
    cone, notes = build_cone(taskdir)
    if cone is None:
        return 'NO_VERIFIER', notes, []
    if not cone:
        return 'NO_REWARD_WRITE', notes, []
    bad = []
    for origin, expr in cone:
        nb, why = classify_expr(expr)
        if nb:
            bad.append((origin, why))
    if bad:
        seen, uniq = set(), []
        for o, w in bad:
            if w not in seen:
                seen.add(w)
                uniq.append((o, w))
        return 'NON_BINARY', notes, uniq
    # did we actually see a literal 0/1 reaching the file?
    proven = any(proven_binary(e) for _, e in cone)
    if not proven:
        return 'REVIEW', notes + ['no literal 0/1 proven to reach reward.txt'], []
    return 'BINARY', notes, []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--json', action='store_true', help='machine-readable report')
    ap.add_argument('--task', help='audit a single task and print its cone')
    ap.add_argument('--root', help='audit a different suite root (used by the self-test)')
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    tasks_dir = Path(args.root).expanduser().resolve() / 'tasks' if args.root else TASKS
    if not tasks_dir.is_dir():
        print(f'ERROR no tasks directory at {tasks_dir}')
        return 1

    if args.task:
        cone, notes = build_cone(tasks_dir / args.task)
        print(f'task={args.task} cone_size={len(cone) if cone is not None else -1}')
        for n in notes:
            print('  NOTE', n)
        for origin, expr in (cone or []):
            nb, why = classify_expr(expr)
            mark = 'NON-BINARY' if nb else 'ok'
            print(f'  [{mark:10s}] {origin:22s} {expr[:110]}')
            if nb:
                print(f'               reason: {why}')
        return 0

    results = {}
    for d in sorted(tasks_dir.iterdir()):
        if d.is_dir():
            results[d.name] = audit_task(d)

    counts = {}
    for t, (v, _, _) in results.items():
        counts[v] = counts.get(v, 0) + 1

    if args.json:
        print(json.dumps({'counts': counts,
                          'tasks': {t: {'verdict': v, 'notes': n,
                                        'reasons': [w for _, w in b]}
                                    for t, (v, n, b) in results.items()}},
                         indent=1))
    else:
        print(f'tasks={len(results)} ' +
              ' '.join(f'{k}={v}' for k, v in sorted(counts.items())))
        for verdict in ('NO_VERIFIER', 'NO_REWARD_WRITE', 'NON_BINARY', 'REVIEW'):
            names = sorted(t for t, (v, _, _) in results.items() if v == verdict)
            if not names:
                continue
            print(f'\n=== {verdict}: {len(names)} ===')
            for t in names:
                print(f'  {t}')
                for _, w in results[t][2][:4]:
                    print(f'      {w}')
                if args.verbose:
                    for n in results[t][1]:
                        print(f'      note: {n}')
    bad = counts.get('NON_BINARY', 0) + counts.get('REVIEW', 0) + \
        counts.get('NO_VERIFIER', 0) + counts.get('NO_REWARD_WRITE', 0)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
