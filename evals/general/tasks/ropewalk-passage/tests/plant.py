#!/usr/bin/env python3
"""Verifier helper for ropewalk-passage.

Extracts the agent's ``repro_ansi_width_*`` reproduction test functions from a
copy of ``src/print.rs``, plants function bodies (agent reproduction, the
golden regression test, hidden width cases) into a copy of ``src/print.rs``.

The golden regression test text is baked into the image at /opt/golden and is
never part of this task tree; the hidden case files are mounted at verify time
only, so neither pair of names is knowable to the trial agent.

Subcommands:
  extract SRC PREFIX
      print JSON {"names": [...], "fns": {name: fn_text}} for every top-level
      test function in SRC whose name starts with PREFIX.
  plant-repros SRC JSONFILE OUT
      append the reproduction functions (from extract output) to a copy of
      SRC, skipping any name already present.
  plant-final SRC GOLDEN H1 H2 H3 OUT
      in a copy of SRC, replace the existing ``test_grapheme_aware_width``
      function body with the golden regression test text (append the golden
      function if the name is absent), then append the three hidden test
      functions, skipping names already present.
"""
import json
import re
import sys


def _top_level_fn(src: str, fn_name: str):
    """Return the span [start, end) of a top-level fn plus its leading #[...]
    attribute line, or None when the fn is not present.

    The fn body is located string-literal-aware from the first balanced
    top-level brace after the signature (parenthesis-aware, tolerant of a
    '-> Return { ... }' style and of a return-type with parens).
    """
    pat = re.compile(r'\bfn ' + re.escape(fn_name) + r'\(')
    m = pat.search(src)
    if not m:
        return None
    fn_start = m.start()
    # back up over the attribute line(s) directly above the fn
    line_start = src.rfind('\n', 0, fn_start) + 1
    seg_start = line_start
    while line_start > 0:
        prev_prev = src.rfind('\n', 0, line_start - 1)
        candidate = prev_prev + 1
        if src[candidate:line_start].strip().startswith('#['):
            seg_start = candidate
            line_start = candidate
        else:
            break
    # find the body-opening brace: the regex matched up to and including the
    # opening '(' of the parameter list, so the paren-skip starts at depth 1
    # and stops right after the matching ')'; then skip whitespace and any
    # optional '-> Type' tokens at paren depth 0 until the body '{'.
    i = m.end()
    depth = 1
    while i < len(src):
        c = src[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                i += 1
                break
        i += 1
    while i < len(src) and src[i] in ' \t\r\n':
        i += 1
    paren = 0
    while i < len(src):
        c = src[i]
        if c == '(':
            paren += 1
        elif c == ')':
            paren -= 1
        elif c == '{' and paren == 0:
            break
        i += 1
    # balance braces string-literal-aware
    depth = 0
    in_str = False
    esc = False
    j = i
    while j < len(src):
        c = src[j]
        if in_str:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    j += 1
                    break
        j += 1
    return (seg_start, j)


def _all_fns(src: str, prefix: str):
    out = {}
    for m in re.finditer(r'\bfn (' + re.escape(prefix) + r'[A-Za-z0-9_]*)\(', src):
        name = m.group(1)
        if name in out:
            continue
        span = _top_level_fn(src, name)
        if span is None:
            continue
        text = src[span[0]:span[1]].rstrip() + '\n'
        out[name] = text
    return out


def main() -> int:
    cmd = sys.argv[1]
    if cmd == 'extract':
        src = open(sys.argv[2], encoding='utf-8').read()
        prefix = sys.argv[3]
        fns = _all_fns(src, prefix)
        print(json.dumps({'names': sorted(fns), 'fns': fns}))
        return 0
    if cmd == 'plant-repros':
        src = open(sys.argv[2], encoding='utf-8').read()
        reqs = json.load(open(sys.argv[3], encoding='utf-8'))
        for name in reqs['names']:
            text = reqs['fns'][name]
            if _top_level_fn(src, name) is None:
                src = src.rstrip() + '\n\n' + text
        open(sys.argv[4], 'w', encoding='utf-8').write(src)
        return 0
    if cmd == 'plant-final':
        src = open(sys.argv[2], encoding='utf-8').read()
        golden = open(sys.argv[3], encoding='utf-8').read().rstrip() + '\n'
        hidden = [open(p, encoding='utf-8').read().rstrip() + '\n'
                  for p in sys.argv[4:7]]
        m = re.search(r'fn test_grapheme_aware_width\(', src)
        if m is not None:
            span = _top_level_fn(src, 'test_grapheme_aware_width')
            if span is not None:
                src = src[:span[0]] + golden + src[span[1]:]
            else:
                src = src.rstrip() + '\n\n' + golden
        else:
            src = src.rstrip() + '\n\n' + golden
        for text in hidden:
            name = re.search(r'\bfn ([A-Za-z0-9_]+)\(', text).group(1)
            if _top_level_fn(src, name) is None:
                src = src.rstrip() + '\n\n' + text
        open(sys.argv[7], 'w', encoding='utf-8').write(src)
        return 0
    raise SystemExit(f'unknown command: {cmd}')


if __name__ == '__main__':
    sys.exit(main())