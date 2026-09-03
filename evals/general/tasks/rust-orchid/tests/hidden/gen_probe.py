#!/usr/bin/env python3
"""qz-probe: independent recompute of quartz-partition frames.

Second, independently-written implementation of the documented TSL algorithm.
Reads a spec + params and prints the canonical frames JSON to stdout.
Also exposes --verify <agent.json> to run deep invariant checks on an
agent-produced file (order, validity, property rules, minimality).

Reference semantics (from the task docs):
  base = strategy 'first' -> first listed choice; 'default' -> [default] or first
  fill = [default] choice of the category, else base
  classes: error > single > ordinary (a choice may carry at most one property)
  frames: base, then single, then ordinary, then error; per group iterate
          parameters/categories/choices in spec order, skipping base choices
  a dedicated frame fixes its focus choice; other categories filled with fill
  repair = among assignments over free categories (no [error] choices, no
          non-base [single] choices) satisfying every constraint, pick the
          minimum number of free categories moved off fill, tie-break by the
          lexicographically smallest tuple of listed-choice positions
  base repair impossible -> unsatisfiable result with the exact reason string
  dedicated frame repair impossible -> frame omitted
  limit > 0 truncates the emitted list; ids "F" + index zfilled to width
  max(2, len(str(n)))
"""
import itertools
import json
import re
import sys

KEYWORDS = {"param", "cat", "choice", "constraint", "default", "single",
            "error", "not", "and", "or", "then", "if", "in"}


def lex(text):
    """Character-state tokenizer: returns (kind, value) list."""
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in " \t\r\n":
            i += 1
            continue
        if ch == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch in "(){}[]:.,=":
            out.append(("SYM", ch))
            i += 1
            continue
        m = re.match(r"-?[0-9]+", text[i:])
        if m:
            out.append(("INT", m.group()))
            i += m.end()
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", text[i:])
        if m:
            w = m.group()
            out.append(("KEY" if w in KEYWORDS else "NAME", w))
            i += m.end()
            continue
        raise ValueError("unlexable char %r at offset %d" % (ch, i))
    out.append(("END", ""))
    return out


class Spec:
    """Validated spec model."""

    def __init__(self):
        self.params = {}
        self.order = []
        self.constraints = []

    def add_param(self, name):
        if name in self.params:
            raise ValueError("duplicate parameter %r" % name)
        self.params[name] = {}
        self.order.append(name)

    def add_cat(self, pname, cname):
        cats = self.params[pname]
        if cname in cats:
            raise ValueError("duplicate category %r.%r" % (pname, cname))
        cats[cname] = []

    def add_choice(self, pname, cname, cname_choice, value, props):
        lst = self.params[pname][cname]
        if any(c[0] == cname_choice for c in lst):
            raise ValueError("duplicate choice %r in %r.%r"
                             % (cname_choice, pname, cname))
        lst.append((cname_choice, value, props, len(lst)))


class Reader:
    def __init__(self, toks):
        self.toks = toks
        self.pos = 0

    def peek_value(self):
        return self.toks[self.pos][1] if self.toks[self.pos][0] != "END" else None

    def take(self):
        t = self.toks[self.pos]
        assert t[0] != "END", "unexpected end of input"
        self.pos += 1
        return t

    def see(self, value):
        return self.peek_value() == value

    def eat(self, value):
        if self.peek_value() != value:
            raise ValueError("expected %r, got %r" % (value, self.peek_value()))
        self.pos += 1

    def name(self, what):
        k, v = self.take()
        if k not in ("NAME", "KEY"):
            raise ValueError("expected a name for %s, got %r" % (what, v))
        return v


def parse_spec(text):
    toks = lex(text)
    rd = Reader(toks)
    spec = Spec()
    while rd.peek_value() is not None:
        if rd.see("param"):
            rd.take()
            pname = rd.name("parameter")
            spec.add_param(pname)
            rd.eat("{")
            while rd.see("cat"):
                rd.take()
                cname = rd.name("category")
                spec.add_cat(pname, cname)
                rd.eat("{")
                while rd.see("choice"):
                    rd.take()
                    ch = rd.name("choice")
                    value = None
                    if rd.see(":"):
                        rd.take()
                        rd.eat("=")
                        k, v = rd.take()
                        if k != "INT":
                            raise ValueError("choice %r needs an integer value" % ch)
                        value = int(v)
                    props = set()
                    while rd.see("["):
                        rd.take()
                        pname_prop = rd.name("property")
                        if pname_prop not in ("default", "single", "error"):
                            raise ValueError("unknown property %r" % pname_prop)
                        props.add(pname_prop)
                        rd.eat("]")
                    spec.add_choice(pname, cname, ch, value, props)
                rd.eat("}")
            rd.eat("}")
        elif rd.see("constraint"):
            rd.take()
            spec.constraints.append(_parse_expr(rd, spec))
        else:
            raise ValueError("expected 'param' or 'constraint', got %r"
                             % rd.peek_value())
    if not spec.order:
        raise ValueError("spec contains no parameters")
    _validate(spec)
    return spec


def _parse_expr(rd, spec):
    if rd.see("if"):
        rd.take()
    left = _parse_or(rd, spec)
    if rd.see("then"):
        rd.take()
        right = _parse_expr(rd, spec)
        return ("=>", left, right)
    return left


def _parse_or(rd, spec):
    parts = [_parse_and(rd, spec)]
    while rd.see("or"):
        rd.take()
        parts.append(_parse_and(rd, spec))
    return parts[0] if len(parts) == 1 else ("or", tuple(parts))


def _parse_and(rd, spec):
    parts = [_parse_not(rd, spec)]
    while rd.see("and"):
        rd.take()
        parts.append(_parse_not(rd, spec))
    return parts[0] if len(parts) == 1 else ("and", tuple(parts))


def _parse_not(rd, spec):
    if rd.see("not"):
        rd.take()
        return ("not", _parse_not(rd, spec))
    return _parse_primary(rd, spec)


def _parse_primary(rd, spec):
    if rd.see("("):
        rd.take()
        e = _parse_expr(rd, spec)
        rd.eat(")")
        return e
    p = rd.name("param")
    rd.eat(".")
    c = rd.name("cat")
    op = rd.take()
    if op[1] == "=":
        ch = rd.name("choice")
        return ("eq", p, c, ch)
    lo = rd.take()
    rd.eat(".")
    rd.eat(".")
    hi = rd.take()
    if lo[0] != "INT" or hi[0] != "INT":
        raise ValueError("range bounds must be integers")
    return ("in", p, c, int(lo[1]), int(hi[1]))


def _validate(spec):
    for pname, cats in spec.params.items():
        for cname, lst in cats.items():
            if not lst:
                raise ValueError("category %r.%r has no choices" % (pname, cname))
            defaults = [c for c in lst if "default" in c[2]]
            if len(defaults) > 1:
                raise ValueError("category %r.%r has two [default] choices"
                                 % (pname, cname))
            if all("error" in c[2] for c in lst):
                raise ValueError("category %r.%r has no non-error choice"
                                 % (pname, cname))
            for c in lst:
                if len(c[2]) > 1:
                    raise ValueError("choice %r carries more than one property"
                                     % c[0])
    for e in spec.constraints:
        _check_expr(e, spec)


def _check_expr(e, spec):
    op = e[0]
    if op in ("eq", "in"):
        _, p, c, *_ = e
        cats = spec.params.get(p)
        if cats is None:
            raise ValueError("constraint references unknown parameter %r" % p)
        if c not in cats:
            raise ValueError("constraint references unknown category %r.%r" % (p, c))
        if op == "eq":
            if not any(x[0] == e[3] for x in cats[c]):
                raise ValueError("constraint references unknown choice %r.%r"
                                 % (c, e[3]))
    elif op == "not":
        _check_expr(e[1], spec)
    elif op in ("and", "or"):
        for sub in e[1]:
            _check_expr(sub, spec)
    elif op == "=>":
        _check_expr(e[1], spec)
        _check_expr(e[2], spec)
    else:
        raise ValueError("bad constraint node %r" % (op,))


def load_params(path):
    with open(path) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("params must be a JSON object")
    strategy = data.get("base_choice_strategy")
    if strategy not in ("first", "default"):
        raise ValueError("base_choice_strategy must be 'first' or 'default'")
    limit = data.get("frame_limit")
    if not isinstance(limit, int) or isinstance(limit, bool) or limit < 0:
        raise ValueError("frame_limit must be an integer >= 0")
    return strategy, limit


def generate(spec, strategy, limit):
    """Recompute the frames document."""
    cats = [(p, c) for p in spec.order for c in spec.params[p]]
    base, fill = {}, {}
    for p, c in cats:
        lst = spec.params[p][c]
        b = next((x[0] for x in lst if "default" in x[2]), None) \
            if strategy == "default" else None
        base[(p, c)] = b if b is not None else lst[0][0]
        fill[(p, c)] = next((x[0] for x in lst if "default" in x[2]),
                            base[(p, c)])

    def choice_of(p, c):
        lst = spec.params[p][c]
        return {x[0]: x for x in lst}

    def make_sel():
        return {p: {c: fill[(p, c)] for c in spec.params[p]} for p in spec.order}

    def truth(e, sel):
        op = e[0]
        if op == "eq":
            _, p, c, ch = e
            return sel[p][c] == ch
        if op == "in":
            _, p, c, lo, hi = e
            ch = sel[p][c]
            val = choice_of(p, c)[ch][1]
            return val is not None and lo <= val <= hi
        if op == "not":
            return not truth(e[1], sel)
        if op == "and":
            return all(truth(x, sel) for x in e[1])
        if op == "or":
            return any(truth(x, sel) for x in e[1])
        return (not truth(e[1], sel)) or truth(e[2], sel)

    def ok(sel):
        return all(truth(cn, sel) for cn in spec.constraints)

    def rank_key(sel, fixed, prefer):
        dev = 0
        vec = []
        for p, c in cats:
            if (p, c) in fixed:
                continue
            if sel[p][c] != prefer[(p, c)]:
                dev += 1
            pos = next(i for i, x in enumerate(spec.params[p][c])
                       if x[0] == sel[p][c])
            vec.append(pos)
        return (dev, tuple(vec))

    def repair(fixed, prefer):
        free = [(p, c) for (p, c) in cats if (p, c) not in fixed]
        pools = []
        for (p, c) in free:
            cands = []
            for ch, val, props, _ in spec.params[p][c]:
                if "error" in props:
                    continue
                if "single" in props and ch != base[(p, c)]:
                    continue
                cands.append(ch)
            pools.append(cands)
        best = None
        for combo in itertools.product(*pools):
            sel = {p: {} for p in spec.order}
            for (pp, cc) in cats:
                sel[pp][cc] = prefer[(pp, cc)]
            for (p, c), ch in zip(free, combo):
                sel[p][c] = ch
            for (p, c), ch in fixed.items():
                sel[p][c] = ch
            if not ok(sel):
                continue
            key = rank_key(sel, fixed, prefer)
            if best is None or key < best[0]:
                best = (key, sel)
        return best[1] if best else None

    result = {"status": "ok", "strategy": strategy, "limit": limit, "frames": []}
    frames = result["frames"]

    # -- base frame
    sel = make_sel()
    if not ok(sel):
        sel = repair({}, fill)
        if sel is None:
            return {"status": "unsatisfiable", "strategy": strategy,
                    "limit": limit, "reason": "no valid base frame exists",
                    "frames": []}
    frames.append({"type": "base", "focus": None, "selections": sel})

    # -- dedicated groups
    for group in ("single", "ordinary", "error"):
        for p, c in cats:
            for ch, val, props, _ in spec.params[p][c]:
                if ch == base[(p, c)]:
                    continue
                cls = "error" if "error" in props else \
                      "single" if "single" in props else "ordinary"
                if cls != group:
                    continue
                sel = make_sel()
                sel[p][c] = ch
                if not ok(sel):
                    sel = repair({(p, c): ch}, fill)
                    if sel is None:
                        continue
                frames.append({
                    "type": group,
                    "focus": {"param": p, "category": c, "choice": ch},
                    "selections": sel,
                })

    if limit > 0:
        del frames[limit:]
    width = max(2, len(str(len(frames))))
    for i, f in enumerate(frames, 1):
        f["id"] = "F" + str(i).zfill(width)
    return result


# ------------------------------------------------------------------ checks
def verify_output(spec_text, params_path, agent_obj, expected):
    """Deep invariant checks on an agent-produced document."""
    problems = []
    if agent_obj.get("status") == "unsatisfiable":
        if agent_obj != expected:
            problems.append("unsatisfiable document differs from recompute")
        return problems
    if agent_obj.get("status") != "ok":
        problems.append("bad status %r" % agent_obj.get("status"))
        return problems
    if agent_obj.get("strategy") != expected.get("strategy") or \
       agent_obj.get("limit") != expected.get("limit"):
        problems.append("strategy/limit mismatch")
    frames = agent_obj.get("frames")
    if not isinstance(frames, list):
        problems.append("frames is not a list")
        return problems

    spec = parse_spec(spec_text)
    strategy, limit = load_params(params_path)
    cats = [(p, c) for p in spec.order for c in spec.params[p]]
    base, fill = {}, {}
    for p, c in cats:
        lst = spec.params[p][c]
        b = next((x[0] for x in lst if "default" in x[2]), None) \
            if strategy == "default" else None
        base[(p, c)] = b if b is not None else lst[0][0]
        fill[(p, c)] = next((x[0] for x in lst if "default" in x[2]),
                            base[(p, c)])

    def truth(e, sel):
        op = e[0]
        if op == "eq":
            return sel[e[1]][e[2]] == e[3]
        if op == "in":
            ch = sel[e[1]][e[2]]
            val = next((x[1] for x in spec.params[e[1]][e[2]] if x[0] == ch), None)
            return val is not None and e[3] <= val <= e[4]
        if op == "not":
            return not truth(e[1], sel)
        if op == "and":
            return all(truth(x, sel) for x in e[1])
        if op == "or":
            return any(truth(x, sel) for x in e[1])
        return (not truth(e[1], sel)) or truth(e[2], sel)

    # structural invariants
    try:
        n = len(frames)
        w = max(2, len(str(n)))
        for i, f in enumerate(frames, 1):
            want_id = "F" + str(i).zfill(w)
            if f.get("id") != want_id:
                problems.append("frame %d id %r != %r" % (i, f.get("id"), want_id))
            if f.get("type") not in ("base", "single", "ordinary", "error"):
                problems.append("frame %d bad type" % i)
                continue
            sel = f.get("selections")
            if not isinstance(sel, dict):
                problems.append("frame %d selections missing" % i)
                continue
            for (p, c) in cats:
                ch = sel.get(p, {}).get(c)
                if ch is None:
                    problems.append("frame %d missing %s.%s" % (i, p, c))
                    continue
                lst = spec.params[p][c]
                if not any(x[0] == ch for x in lst):
                    problems.append("frame %d unknown choice %s.%s=%r" % (i, p, c, ch))
        # order: base first; groups single/ordinary/error in that order
        seq = [f.get("type") for f in frames]
        if seq and seq[0] != "base":
            problems.append("first frame is not base")
        allowed = {"single": 0, "ordinary": 1, "error": 2}
        last = -1
        for t in seq[1:]:
            if t not in allowed:
                problems.append("unexpected group %r" % t)
                continue
            if allowed[t] < last:
                problems.append("group order violated around %r" % t)
            last = max(last, allowed[t])
        # per-frame validity + property rules + focus correctness
        for i, f in enumerate(frames, 1):
            sel = f["selections"]
            if not all(truth(cn, sel) for cn in spec.constraints):
                problems.append("frame %d violates a constraint" % i)
            focused = set()
            foc = f.get("focus")
            if foc is not None:
                if foc.get("choice") != sel.get(foc.get("param"), {}).get(foc.get("category")):
                    problems.append("frame %d focus not selected" % i)
                focused.add((foc.get("param"), foc.get("category")))
            for (p, c) in cats:
                ch = sel.get(p, {}).get(c)
                lst = spec.params[p][c]
                entry = next((x for x in lst if x[0] == ch), None)
                if entry is None:
                    continue
                _, _, props, _ = entry
                if "error" in props and not (f["type"] == "error" and
                                             (p, c) in focused):
                    problems.append("frame %d error choice off-focus" % i)
                if "single" in props and ch != base[(p, c)] and \
                        not (f["type"] == "single" and (p, c) in focused):
                    problems.append("frame %d single choice off-focus" % i)
            # frame focus must not coincide with base choice
            if foc is not None and foc.get("choice") == base.get((foc.get("param"), foc.get("category"))):
                problems.append("frame %d focuses on a base choice" % i)
        if limit and len(frames) > limit:
            problems.append("frame_limit %d exceeded" % limit)
    except Exception as exc:
        problems.append("invariant walk failed: %s" % exc)
    return problems


def main(argv):
    if argv[1:2] == ["--verify"]:
        spec_text = open(argv[2]).read()
        params_path = argv[3]
        agent_path = argv[4]
        agent_obj = json.load(open(agent_path))
        expected = generate(parse_spec(spec_text), *load_params(params_path))
        problems = verify_output(spec_text, params_path, agent_obj, expected)
        if agent_obj != expected:
            problems.append("document differs from independent recompute")
        if problems:
            print("PROBLEMS:", "; ".join(problems))
            return 1
        print("OK")
        return 0
    if len(argv) != 3:
        print("usage: probe.py <spec.tsl> <params.json>", file=sys.stderr)
        return 2
    spec = parse_spec(open(argv[1]).read())
    strategy, limit = load_params(argv[2])
    print(json.dumps(generate(spec, strategy, limit), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))