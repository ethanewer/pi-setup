#!/bin/bash
# Oracle for rust-orchid: install the reference category-partition
# frame generator as the deliverable and produce the visible frames.json.
# Runs only against fixtures shipped in the image, never verifier files.
set -eu

cat > /app/generate_cases.py <<'PYEOF'
#!/usr/bin/env python3
"""quartz-partition: category-partition test-frame generator (reference).

Implements the documented TSL algorithm:
  - parse TSL spec (params/cats/choices with properties, constraints)
  - base choice strategy from params.json ("first"|"default")
  - fill = default-or-base
  - frames: base, then single, then ordinary, then error groups
  - repair = minimal-deviation valid assignment, lexicographic tie-break
  - unsatisfiable base -> {"status":"unsatisfiable", ...}
"""
import json
import re
import sys
from itertools import product

# ---------------------------------------------------------------- tokenize
_TOKEN = re.compile(r"""
      (?P<WS>\s+)
    | (?P<COMMENT>\#[^\n]*)
    | (?P<NAME>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<INT>-?[0-9]+)
    | (?P<SYM>[(){}\[\]:.,=])
""", re.X)


def tokenize(text):
    toks = []
    for m in _TOKEN.finditer(text):
        if m.lastgroup in ("WS", "COMMENT"):
            continue
        toks.append((m.lastgroup, m.group()))
    toks.append(("EOF", ""))
    return toks


class SpecError(Exception):
    pass


# ---------------------------------------------------------------- parser
class Parser:
    def __init__(self, text):
        self.toks = tokenize(text)
        self.i = 0

    def peek(self, value=None):
        return self.toks[self.i][1] == value if value is not None else self.toks[self.i]

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def expect(self, value):
        k, v = self.next()
        if v != value:
            raise SpecError("expected %r, got %r" % (value, v))

    def expect_name(self, what):
        k, v = self.next()
        if k != "NAME":
            raise SpecError("expected a name for %s, got %r" % (what, v))
        return v

    def parse(self):
        params = []
        constraints = []
        names = {}
        while self.peek()[0] != "EOF":
            if self.peek("param"):
                self.next()
                params.append(self.parse_param(names))
            elif self.peek("constraint"):
                self.next()
                constraints.append(self.parse_expr())
            else:
                raise SpecError("expected 'param' or 'constraint', got %r"
                                % self.peek()[1])
        if not params:
            raise SpecError("spec contains no parameters")
        for expr in constraints:
            self.check_expr(expr, names)
        return params, constraints

    def parse_param(self, names):
        pname = self.expect_name("parameter")
        if pname in names:
            raise SpecError("duplicate parameter %r" % pname)
        prm = {"name": pname, "cats": []}
        catnames = set()
        self.expect("{")
        while True:
            if self.peek("cat"):
                self.next()
                cname = self.expect_name("category")
                if cname in catnames:
                    raise SpecError("duplicate category %r in parameter %r"
                                    % (cname, pname))
                catnames.add(cname)
                cat = {"name": cname, "choices": []}
                self.expect("{")
                props_seen = set()
                while not self.peek("}"):
                    if not self.peek("choice"):
                        raise SpecError("expected 'choice' in category %r.%r"
                                        % (pname, cname))
                    self.next()
                    chname = self.expect_name("choice")
                    for cc in cat["choices"]:
                        if cc["name"] == chname:
                            raise SpecError("duplicate choice %r in category %r.%r"
                                            % (chname, pname, cname))
                    value = None
                    if self.peek(":") and self.toks[self.i + 1][1] == "=":
                        self.next()
                        self.next()
                        k, v = self.next()
                        if k != "INT":
                            raise SpecError("choice %r needs an integer value" % chname)
                        value = int(v)
                    props = set()
                    while self.peek("["):
                        self.next()
                        p = self.expect_name("property")
                        if p not in ("default", "single", "error"):
                            raise SpecError("unknown property %r" % p)
                        props.add(p)
                        self.expect("]")
                    if len(props) > 1:
                        raise SpecError("choice %r carries more than one property" % chname)
                    if "default" in props and "default" in props_seen:
                        raise SpecError("category %r.%r has two [default] choices"
                                        % (pname, cname))
                    if "default" in props:
                        props_seen.add("default")
                    cat["choices"].append({"name": chname, "value": value,
                                           "props": props})
                self.expect("}")
                if not cat["choices"]:
                    raise SpecError("category %r.%r has no choices" % (pname, cname))
                if all("error" in c["props"] for c in cat["choices"]):
                    raise SpecError("category %r.%r has no non-error choice"
                                    % (pname, cname))
                prm["cats"].append(cat)
            else:
                break
        if not prm["cats"]:
            raise SpecError("parameter %r has no categories" % pname)
        self.expect("}")
        names[pname] = prm
        return prm

    def parse_expr(self):
        # imp := 'if'? or_expr ('then' or_expr)?   (then right-assoc)
        if self.peek("if"):
            self.next()
        left = self.parse_or()
        if self.peek("then"):
            self.next()
            right = self.parse_expr()
            return ("imp", left, right)
        return left

    def parse_or(self):
        parts = [self.parse_and()]
        while self.peek("or"):
            self.next()
            parts.append(self.parse_and())
        if len(parts) == 1:
            return parts[0]
        return ("or", parts)

    def parse_and(self):
        parts = [self.parse_not()]
        while self.peek("and"):
            self.next()
            parts.append(self.parse_not())
        if len(parts) == 1:
            return parts[0]
        return ("and", parts)

    def parse_not(self):
        if self.peek("not"):
            self.next()
            return ("not", self.parse_not())
        return self.parse_primary()

    def parse_primary(self):
        if self.peek("("):
            self.next()
            e = self.parse_expr()
            self.expect(")")
            return e
        return self.parse_atom()

    def parse_atom(self):
        p = self.expect_name("atom parameter")
        self.expect(".")
        c = self.expect_name("atom category")
        op = self.next()
        if op[1] == "=":
            ch = self.expect_name("atom choice")
            return ("eq", p, c, ch)
        if op[1] == "in":
            k, lo = self.next()
            if k != "INT":
                raise SpecError("range lower bound must be an integer")
            self.expect(".")
            self.expect(".")
            k, hi = self.next()
            if k != "INT":
                raise SpecError("range upper bound must be an integer")
            return ("in", p, c, int(lo), int(hi))
        raise SpecError("expected '=' or 'in' in atom, got %r" % op[1])

    def check_expr(self, e, names):
        op = e[0]
        if op in ("eq", "in"):
            _, p, c, *_ = e
            if p not in names:
                raise SpecError("constraint references unknown parameter %r" % p)
            prm = names[p]
            for cc in prm["cats"]:
                if cc["name"] == c:
                    if op == "eq":
                        ch = e[3]
                        if not any(x["name"] == ch for x in cc["choices"]):
                            raise SpecError("constraint references unknown choice %r.%r"
                                            % (c, ch))
                    return
            raise SpecError("constraint references unknown category %r.%r" % (p, c))
        if op == "not":
            self.check_expr(e[1], names)
            return
        if op in ("and", "or"):
            for sub in e[1]:
                self.check_expr(sub, names)
            return
        if op == "imp":
            self.check_expr(e[1], names)
            self.check_expr(e[2], names)
            return
        raise SpecError("internal: unknown node %r" % (op,))


# ---------------------------------------------------------------- semantics
def classify(choice, base_name):
    props = choice["props"]
    if "error" in props:
        return "error"
    if "single" in props:
        return "single"
    return "ordinary"


def base_of(cat, strategy):
    if strategy == "default":
        for c in cat["choices"]:
            if "default" in c["props"]:
                return c["name"]
    return cat["choices"][0]["name"]


def fill_of(cat, base_name):
    for c in cat["choices"]:
        if "default" in c["props"]:
            return c["name"]
    return base_name


def load_params(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        raise SpecError("params file unreadable or not JSON")
    if not isinstance(data, dict):
        raise SpecError("params must be a JSON object")
    strat = data.get("base_choice_strategy")
    if strat not in ("first", "default"):
        raise SpecError("base_choice_strategy must be \"first\" or \"default\"")
    lim = data.get("frame_limit")
    if not isinstance(lim, int) or isinstance(lim, bool) or lim < 0:
        raise SpecError("frame_limit must be an integer >= 0")
    return strat, lim


def build(params, constraints, strategy, limit):
    cats = [(p, cat) for p in params for cat in p["cats"]]
    base = {}
    fill = {}
    for p, cat in cats:
        base[(p["name"], cat["name"])] = base_of(cat, strategy)
        fill[(p["name"], cat["name"])] = fill_of(cat, base[(p["name"], cat["name"])])

    def mk_sel():
        return {p["name"]: {cat["name"]: fill[(p["name"], cat["name"])]
                            for cat in p["cats"]} for p in params}

    def evaluate(e, sel):
        op = e[0]
        if op == "eq":
            _, p, c, ch = e
            return sel[p][c] == ch
        if op == "in":
            _, p, c, lo, hi = e
            ch = sel[p][c]
            val = None
            for p0, cat in cats:
                if p0["name"] == p and cat["name"] == c:
                    for cc in cat["choices"]:
                        if cc["name"] == ch:
                            val = cc["value"]
            return val is not None and lo <= val <= hi
        if op == "not":
            return not evaluate(e[1], sel)
        if op == "and":
            return all(evaluate(x, sel) for x in e[1])
        if op == "or":
            return any(evaluate(x, sel) for x in e[1])
        if op == "imp":
            return (not evaluate(e[1], sel)) or evaluate(e[2], sel)
        raise SpecError("internal: bad expr %r" % (e,))

    def valid(sel):
        return all(evaluate(e, sel) for e in constraints)

    def candidates_for(pname, cname):
        out = []
        for p, cat in cats:
            if p["name"] == pname and cat["name"] == cname:
                for c in cat["choices"]:
                    if "error" in c["props"]:
                        continue
                    if "single" in c["props"] and c["name"] != base[(pname, cname)]:
                        continue
                    out.append(c["name"])
                break
        return out

    def repaired(fixed, prefer):
        free = [cid for cid in cats_keys if cid not in fixed]
        cands = {cid: candidates_for(*cid) for cid in free}
        best = None
        for combo in product(*(cands[cid] for cid in free)):
            sel = mk_sel()
            for cid, ch in fixed.items():
                sel[cid[0]][cid[1]] = ch
            for cid, ch in zip(free, combo):
                sel[cid[0]][cid[1]] = ch
            if not valid(sel):
                continue
            dev = sum(1 for cid in free if sel[cid[0]][cid[1]] != prefer[cid])
            idx = []
            for cid in free:
                pname, cname = cid
                pos = 0
                for p, cat in cats:
                    if p["name"] == pname and cat["name"] == cname:
                        for i, cc in enumerate(cat["choices"]):
                            if cc["name"] == sel[pname][cname]:
                                pos = i
                idx.append(pos)
            if best is None:
                best = (dev, tuple(idx), sel)
            else:
                if (dev, tuple(idx)) < (best[0], best[1]):
                    best = (dev, tuple(idx), sel)
        return best[2] if best else None

    cats_keys = [(p["name"], cat["name"]) for p, cat in cats]

    def focus_obj(pname, cname, ch):
        return {"param": pname, "category": cname, "choice": ch}

    frames = []
    out = {"status": "ok", "strategy": strategy, "limit": limit, "frames": frames}

    # --- 1. base frame (repair if needed; unsat if impossible)
    sel = mk_sel()
    if valid(sel):
        frames.append({"id": None, "type": "base", "focus": None,
                       "selections": sel})
    else:
        best = repaired({}, fill)
        if best is None:
            return {"status": "unsatisfiable", "strategy": strategy,
                    "limit": limit, "reason": "no valid base frame exists",
                    "frames": []}
        frames.append({"id": None, "type": "base", "focus": None,
                       "selections": best})

    # --- 2/3/4. dedicated groups in order: single, ordinary, error
    for group in ("single", "ordinary", "error"):
        for pname, cname in cats_keys:
            for p, cat in cats:
                if p["name"] == pname and cat["name"] == cname:
                    for c in cat["choices"]:
                        if c["name"] == base[(pname, cname)]:
                            continue
                        if classify(c, None) != group:
                            continue
                        sel = mk_sel()
                        sel[pname][cname] = c["name"]
                        if valid(sel):
                            frames.append({"id": None, "type": group,
                                           "focus": focus_obj(pname, cname, c["name"]),
                                           "selections": sel})
                        else:
                            fixed = {(pname, cname): c["name"]}
                            best = repaired(fixed, fill)
                            if best is not None:
                                frames.append({"id": None, "type": group,
                                               "focus": focus_obj(pname, cname, c["name"]),
                                               "selections": best})
                    break

    if limit > 0:
        frames[:] = frames[:limit]
    width = max(2, len(str(len(frames))))
    for i, f in enumerate(frames, 1):
        f["id"] = "F" + str(i).zfill(width)
    return out


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: generate_cases.py <spec.tsl> <params.json> <frames.json>\n")
        return 3
    spec_path, params_path, out_path = argv[1], argv[2], argv[3]
    try:
        with open(spec_path) as fh:
            text = fh.read()
    except OSError as exc:
        sys.stderr.write("TSL error: cannot read spec: %s\n" % exc)
        return 1
    try:
        pr = Parser(text)
        params, constraints = pr.parse()
    except SpecError as exc:
        sys.stderr.write("TSL error: %s\n" % exc)
        return 1
    try:
        strategy, limit = load_params(params_path)
    except SpecError as exc:
        sys.stderr.write("params error: %s\n" % exc)
        return 2
    try:
        result = build(params, constraints, strategy, limit)
        payload = json.dumps(result, indent=2) + "\n"
        with open(out_path, "w") as fh:
            fh.write(payload)
    except OSError as exc:
        sys.stderr.write("output error: %s\n" % exc)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF

python3 /app/generate_cases.py /app/specs/printer.tsl /app/params.json /app/frames.json

echo "solve.sh done"
python3 -c "import json; d=json.load(open('/app/frames.json')); print('status=%s frames=%d' % (d['status'], len(d['frames'])))"