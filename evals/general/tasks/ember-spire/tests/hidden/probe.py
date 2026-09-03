#!/usr/bin/env python3
"""ember-spire verifier probe.

Independent reference implementation of the documented manifest-merge engine
(recomputed from scratch, no shared code with the deliverable) plus a runner
that executes /app/render_chart.py over the visible chart and hidden charts
and compares exact exit codes, stderr tokens, file sets and canonical JSON
bytes. Exits 0 only when every case passes.
"""
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

DELIVERABLE = "/app/render_chart.py"
VISIBLE_CHART = "/app/charts/acme-web"
VISIBLE_OVERRIDES = ["/app/overrides/prod.json", "/app/overrides/edge.json"]
VISIBLE_OUT = "/app/rendered"
HIDDEN = "/tests/hidden/charts"
HIDDEN_VALUES = "/tests/hidden/values"

SEG = r"[A-Za-z0-9_-]+"
PH = re.compile(r"\{\{\s*\.(" + SEG + r"(?:\." + SEG + r")*)\s*\}\}")
POLICIES = {"replace", "append", "merge-by-key"}
MISS = object()

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg, file=sys.stderr)


class ExpectedErr(Exception):
    """Expected failure: .code exit code, .token must appear in stderr."""

    def __init__(self, code, token):
        super().__init__(token)
        self.code = code
        self.token = token


def deep_merge(base, overlay):
    """null deletes a key; both-dict recurses; anything else replaces."""
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for k, v in overlay.items():
            if v is None:
                out.pop(k, None)
            elif k in out and isinstance(out[k], dict) and isinstance(v, dict):
                out[k] = deep_merge(out[k], v)
            else:
                out[k] = v
        return out
    return overlay


def canonical(obj):
    return json.dumps(obj, sort_keys=True, indent=2) + "\n"


def get_at(root, segs):
    cur = root
    for s in segs:
        if isinstance(cur, dict) and s in cur:
            cur = cur[s]
        else:
            return MISS
    return cur


class Reference:
    """The documented engine, written independently of the deliverable."""

    def __init__(self, chart_dir, values_files):
        self.chart_dir = chart_dir
        self.values_files = values_files
        self._load()
        self._merge_values()
        self._check_strategy()

    def _load(self):
        cp = os.path.join(self.chart_dir, "chart.json")
        if not os.path.isfile(cp):
            raise ExpectedErr(3, "chart.json not found")
        try:
            with open(cp, "r", encoding="utf-8") as fh:
                chart = json.load(fh)
        except (OSError, ValueError):
            raise ExpectedErr(3, "chart")
        if not isinstance(chart, dict):
            raise ExpectedErr(3, "chart.json is not a JSON object")
        self.tdir = os.path.join(self.chart_dir, "templates")
        if not os.path.isdir(self.tdir):
            raise ExpectedErr(3, "templates directory not found")
        base_values = chart.get("values", {})
        if not isinstance(base_values, dict):
            raise ExpectedErr(3, "chart values is not a JSON object")
        self.base_values = base_values
        strat = chart.get("strategy", {})
        if not isinstance(strat, dict):
            raise ExpectedErr(3, "chart strategy is not a JSON object")
        self.strategy = strat

    def _merge_values(self):
        merged = copy.deepcopy(self.base_values)
        for vf in self.values_files:
            try:
                with open(vf, "r", encoding="utf-8") as fh:
                    layer = json.load(fh)
            except (OSError, ValueError):
                raise ExpectedErr(4, "values file")
            if not isinstance(layer, dict):
                raise ExpectedErr(4, "values file is not a JSON object")
            merged = deep_merge(merged, layer)
        self.final = merged

    def _check_strategy(self):
        for tpl, entries in self.strategy.items():
            if not os.path.isfile(os.path.join(self.tdir, tpl + ".json")):
                raise ExpectedErr(3, "strategy references unknown template")
            if not isinstance(entries, dict):
                raise ExpectedErr(3, "strategy")
            for path, desc in entries.items():
                if not isinstance(desc, dict):
                    raise ExpectedErr(3, "strategy")
                pol = desc.get("policy")
                if pol is None:
                    raise ExpectedErr(3, "has no policy")
                if pol not in POLICIES:
                    raise ExpectedErr(3, "unknown merge policy " + str(pol))
                if "from" not in desc:
                    raise ExpectedErr(3, "has no from path")
                if pol == "merge-by-key" and not desc.get("key"):
                    raise ExpectedErr(3, "requires a key field")

    def substitute(self, node, tpl):
        if isinstance(node, dict):
            return {k: self.substitute(v, tpl) for k, v in node.items()}
        if isinstance(node, list):
            return [self.substitute(v, tpl) for v in node]
        if isinstance(node, str):
            m = PH.fullmatch(node)
            if m:
                got = get_at(self.final, m.group(1).split("."))
                if got is MISS:
                    raise ExpectedErr(4, "missing value path")
                return copy.deepcopy(got)
            if "{{" in node or "}}" in node:
                raise ExpectedErr(4, "malformed placeholder")
            return node
        return node

    def _key_of(self, item, segs, tpl, path):
        if not isinstance(item, dict):
            raise ExpectedErr(4, "has no key")
        cur = item
        for s in segs:
            if isinstance(cur, dict) and s in cur:
                cur = cur[s]
            else:
                raise ExpectedErr(4, "has no key")
        return cur

    def _merge_by_key(self, base, over, key_segs, tpl, path):
        out = []
        pos = {}
        for it in base:
            k = self._key_of(it, key_segs, tpl, path)
            if k in pos:
                out.append(it)
            else:
                pos[k] = len(out)
                out.append(it)
        for it in over:
            k = self._key_of(it, key_segs, tpl, path)
            if k in pos:
                out[pos[k]] = deep_merge(out[pos[k]], it)
            else:
                pos[k] = len(out)
                out.append(it)
        return out

    def _apply(self, resource, tpl):
        for path, desc in self.strategy.get(tpl, {}).items():
            segs = path.split(".")
            cur = get_at(resource, segs)
            if cur is not MISS and not isinstance(cur, list):
                raise ExpectedErr(4, "merge target")
            base = [] if cur is MISS else cur
            got = get_at(self.final, desc["from"].split("."))
            if got is MISS:
                over = []
            elif not isinstance(got, list):
                raise ExpectedErr(4, "is not a list")
            else:
                over = got
            pol = desc["policy"]
            if pol == "replace":
                result = over
            elif pol == "append":
                result = base + over
            else:
                result = self._merge_by_key(base, over, desc["key"].split("."), tpl, path)
            node = resource
            for s in segs[:-1]:
                nxt = node.get(s)
                if not isinstance(nxt, dict):
                    nxt = {}
                    node[s] = nxt
                node = nxt
            node[segs[-1]] = result

    def expected_files(self):
        """Return {filename: canonical-json-string}; raise ExpectedErr on error."""
        plan = {}
        for f in sorted(x for x in os.listdir(self.tdir) if x.endswith(".json")):
            tpl = f[:-5]
            try:
                with open(os.path.join(self.tdir, f), "r", encoding="utf-8") as fh:
                    doc = json.load(fh)
            except (OSError, ValueError):
                raise ExpectedErr(4, "template")
            if isinstance(doc, dict):
                resources = [doc]
            elif isinstance(doc, list) and all(isinstance(e, dict) for e in doc):
                resources = doc
            else:
                raise ExpectedErr(4, "must be a JSON object or array")
            rendered = []
            for r in resources:
                rr = self.substitute(r, f)
                self._apply(rr, tpl)
                rendered.append(rr)
            if len(rendered) == 1 and isinstance(doc, dict):
                plan[tpl + ".json"] = canonical(rendered[0])
            else:
                width = len(str(len(rendered)))
                for i, r in enumerate(rendered):
                    plan[tpl + "-" + str(i).zfill(width) + ".json"] = canonical(r)
        return plan


def run_deliverable(chart, values_files, out_dir):
    cmd = [sys.executable, DELIVERABLE, chart]
    for vf in values_files:
        cmd += ["--values", vf]
    cmd += ["--out", out_dir]
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        fail("deliverable timed out for %s" % chart)
        return None


def compare_outputs(actual_dir, expected, label):
    if not os.path.isdir(actual_dir):
        fail("%s: output dir missing" % label)
        return
    got_names = set(os.listdir(actual_dir))
    want_names = set(expected.keys())
    if got_names != want_names:
        fail("%s: file set mismatch\n  got: %s\n  want: %s"
             % (label, sorted(got_names), sorted(want_names)))
        return
    for name in want_names:
        try:
            with open(os.path.join(actual_dir, name), "r", encoding="utf-8") as fh:
                content = fh.read()
        except OSError as exc:
            fail("%s: cannot read %s: %s" % (label, name, exc))
            continue
        if content != expected[name]:
            fail("%s: canonical JSON mismatch in %s" % (label, name))


def happy_case(label, chart, values_files, out_pre_junk=False):
    try:
        expected = Reference(chart, values_files).expected_files()
        exp_code = 0
    except ExpectedErr as exc:
        fail("%s: reference engine itself errored (%s)" % (label, exc))
        return
    tmp = tempfile.mkdtemp(prefix="dsmm_")
    out = os.path.join(tmp, "out")
    if out_pre_junk:
        os.makedirs(out)
        with open(os.path.join(out, "junk.txt"), "w") as fh:
            fh.write("stale")
        os.makedirs(os.path.join(out, "stale"), exist_ok=True)
    r = run_deliverable(chart, values_files, out)
    if r is None:
        return
    if r.returncode != exp_code:
        fail("%s: exit %d expected 0; stderr: %s" % (label, r.returncode, r.stderr.strip()))
        return
    compare_outputs(out, expected, label)
    shutil.rmtree(tmp, ignore_errors=True)


def error_case(label, chart, values_files, exp_code, token):
    try:
        Reference(chart, values_files).expected_files()
        # reference computed a successful plan; the deliverable must still
        # fail, which means either the reference or the case table is wrong.
        fail("%s: reference engine unexpectedly succeeded (case table bug)" % label)
        return
    except ExpectedErr as exc:
        if exc.code != exp_code:
            fail("%s: reference expects exit %d (got %d)" % (label, exp_code, exc.code))
            return
    tmp = tempfile.mkdtemp(prefix="dsmm_")
    out = os.path.join(tmp, "out")
    r = run_deliverable(chart, values_files, out)
    if r is None:
        return
    if r.returncode != exp_code:
        fail("%s: exit %d expected %d; stderr: %s"
             % (label, r.returncode, exp_code, r.stderr.strip()))
    elif token not in (r.stderr or ""):
        fail("%s: token %r missing from stderr: %s"
             % (label, token, r.stderr.strip()))
    shutil.rmtree(tmp, ignore_errors=True)


def usage_case(label, args, exp_code, token):
    tmp = tempfile.mkdtemp(prefix="dsmm_")
    cmd = [sys.executable, DELIVERABLE] + [a.replace("@OUT@", tmp) for a in args]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        fail("%s: timed out" % label)
        shutil.rmtree(tmp, ignore_errors=True)
        return
    if r.returncode != exp_code:
        fail("%s: exit %d expected %d" % (label, r.returncode, exp_code))
    elif token not in (r.stderr or ""):
        fail("%s: token %r missing from stderr: %s" % (label, token, r.stderr.strip()))
    shutil.rmtree(tmp, ignore_errors=True)


def main():
    if not os.path.isfile(DELIVERABLE):
        fail("deliverable %s missing" % DELIVERABLE)
        return 1

    # ---- 1. visible chart, defaults only and documented overrides ----
    happy_case("visible-defaults", VISIBLE_CHART, [])
    happy_case("visible-prod-edge", VISIBLE_CHART, VISIBLE_OVERRIDES)
    happy_case("visible-prod-edge-cleared-out", VISIBLE_CHART, VISIBLE_OVERRIDES,
               out_pre_junk=True)

    # ---- 2. /app/rendered deliverable must equal the visible recompute ----
    try:
        expected = Reference(VISIBLE_CHART, VISIBLE_OVERRIDES).expected_files()
    except ExpectedErr as exc:
        fail("reference error on visible chart: %s" % exc)
        return 1
    compare_outputs(VISIBLE_OUT, expected, "rendered-deliverable")

    # ---- 3. hidden happy charts ----
    happy_case("nest", os.path.join(HIDDEN, "nest"),
               [os.path.join(HIDDEN_VALUES, "nest_v1.json"),
                os.path.join(HIDDEN_VALUES, "nest_v2.json")])
    happy_case("matrix", os.path.join(HIDDEN, "matrix"),
               [os.path.join(HIDDEN_VALUES, "matrix_v1.json")])
    happy_case("matrix-empty-layer", os.path.join(HIDDEN, "matrix"),
               [os.path.join(HIDDEN_VALUES, "empty.json")])
    happy_case("bare-no-values", os.path.join(HIDDEN, "bare"), [])
    happy_case("bare-empty-values", os.path.join(HIDDEN, "bare"),
               [os.path.join(HIDDEN_VALUES, "empty.json")])
    happy_case("void-empty-templates", os.path.join(HIDDEN, "void"), [])
    happy_case("visible-bad-values-cwd-relative", "/app/charts/acme-web",
               ["overrides/prod.json"])  # relative resolution vs /app cwd

    # ---- 4. hidden error charts ----
    H = lambda n: os.path.join(HIDDEN, n)  # noqa: E731
    error_case("err-unknown-policy", H("err_unknown_policy"), [], 3, "unknown merge policy")
    error_case("err-missing-policy", H("err_missing_policy"), [], 3, "has no policy")
    error_case("err-missing-from", H("err_missing_from"), [], 3, "has no from path")
    error_case("err-merge-no-key", H("err_merge_no_key"), [], 3, "requires a key field")
    error_case("err-unknown-template", H("err_unknown_template"), [], 3, "strategy references unknown template")
    error_case("err-no-templates", H("err_no_templates"), [], 3, "templates directory not found")
    error_case("err-no-chart-json", H("err_no_chart_json"), [], 3, "chart.json not found")
    error_case("err-bad-chart-json", H("err_bad_chart_json"), [], 3, "chart")
    error_case("err-missing-value-path", H("err_missing_value_path"), [], 4, "missing value path")
    error_case("err-malformed-placeholder", H("err_malformed_placeholder"), [], 4, "malformed placeholder")
    error_case("err-nonlist-from", H("err_nonlist_from"), [], 4, "is not a list")
    error_case("err-base-not-list", H("err_base_not_list"), [], 4, "merge target")
    error_case("err-item-no-key", H("err_item_no_key"), [], 4, "has no key")
    error_case("err-template-shape", H("err_template_shape"), [], 4, "must be a JSON object or array")

    # ---- 5. bad values files (against the visible chart) ----
    error_case("values-malformed-json", VISIBLE_CHART,
               [os.path.join(HIDDEN_VALUES, "bad_json.json")], 4, "values file")
    error_case("values-not-object", VISIBLE_CHART,
               [os.path.join(HIDDEN_VALUES, "bad_shape.json")], 4, "values file is not a JSON object")
    error_case("values-missing-file", VISIBLE_CHART,
               ["/tests/hidden/values/does_not_exist.json"], 4, "values file")

    # ---- 6. usage errors ----
    usage_case("usage-missing-out", [VISIBLE_CHART], 2, "usage error")
    usage_case("usage-unknown-option", [VISIBLE_CHART, "--bogus", "@OUT@"], 2, "usage error")

    if failures:
        print("PROBE FAILURES: %d" % len(failures), file=sys.stderr)
        return 1
    print("PROBE OK: all manifest-merge cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())