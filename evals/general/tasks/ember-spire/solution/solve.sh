#!/bin/bash
#
# ember-spire oracle. Authors the CLI deliverable /app/render_chart.py
# implementing the documented manifest-merge engine (values precedence,
# null-deletes-a-key, {{ .path }} substitution, per-template array strategy
# table, canonical JSON output, documented exit codes), then runs it on the
# visible chart to produce /app/rendered. Never reads the verifier files.
set -euo pipefail

cat > /app/render_chart.py <<'PYEOF'
#!/usr/bin/env python3
"""ember-spire render CLI.

Renders a chart (chart.json values + templates/*.json skeletons) with layers
of values files. Deep map merge with values precedence (later files override
earlier), null deletes a key, typed {{ .path }} substitution, and a per-
template array-merge policy table. Emits canonical sorted JSON per resource.

Python 3.12 standard library only. Deterministic.
"""
import copy, json, os, re, shutil, sys

SEG = r"[A-Za-z0-9_-]+"
PLACEHOLDER = re.compile(r"\{\{\s*\.(" + SEG + r"(?:\." + SEG + r")*)\s*\}\}")
POLICIES = ("replace", "append", "merge-by-key")


class UsageError(Exception):
    pass


class ChartError(Exception):
    pass


class RenderError(Exception):
    pass


def deep_merge(base, overlay):
    """Merge overlay into base (returning a new value). null deletes a key."""
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


def read_json(path, errors_cls, what):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        raise errors_cls(what + " not found: " + path)
    except (OSError, ValueError) as exc:
        raise errors_cls(what + " unreadable/malformed: " + path + " (" + str(exc) + ")")
    return data


class Engine:
    def __init__(self, chart_dir, values_files):
        self.chart_dir = chart_dir
        self.values_files = values_files
        self._load_chart()
        self._resolve_values()
        self._validate_strategy()

    def _load_chart(self):
        chart_path = os.path.join(self.chart_dir, "chart.json")
        if not os.path.isfile(chart_path):
            raise ChartError("chart.json not found in " + self.chart_dir)
        chart = read_json(chart_path, ChartError, "chart.json")
        if not isinstance(chart, dict):
            raise ChartError("chart.json is not a JSON object")
        self.templates_dir = os.path.join(self.chart_dir, "templates")
        if not os.path.isdir(self.templates_dir):
            raise ChartError("templates directory not found")
        self.values = chart.get("values", {})
        if not isinstance(self.values, dict):
            raise ChartError("chart values is not a JSON object")
        self.strategy = chart.get("strategy", {})
        if not isinstance(self.strategy, dict):
            raise ChartError("chart strategy is not a JSON object")

    def _resolve_values(self):
        result = copy.deepcopy(self.values)
        for f in self.values_files:
            layer = read_json(f, RenderError, "values file")
            if not isinstance(layer, dict):
                raise RenderError("values file is not a JSON object: " + f)
            result = deep_merge(result, layer)
        self.final_values = result

    def _validate_strategy(self):
        for tpl in self.strategy:
            if not os.path.isfile(os.path.join(self.templates_dir, tpl + ".json")):
                raise ChartError("strategy references unknown template: " + tpl)
            entries = self.strategy[tpl]
            if not isinstance(entries, dict):
                raise ChartError("strategy entries for " + tpl + " are not an object")
            for path, desc in entries.items():
                if not isinstance(desc, dict):
                    raise ChartError("strategy entry for " + tpl + " at " + path + " is not an object")
                policy = desc.get("policy")
                if policy is None:
                    raise ChartError("strategy entry for " + tpl + " at " + path + " has no policy")
                if policy not in POLICIES:
                    raise ChartError("unknown merge policy " + str(policy) + " for " + tpl + " at " + path)
                if "from" not in desc:
                    raise ChartError("strategy entry for " + tpl + " at " + path + " has no from path")
                if policy == "merge-by-key" and not desc.get("key"):
                    raise ChartError("merge-by-key strategy for " + tpl + " at " + path + " requires a key field")

    def _resolve(self, path, depth):
        cur = self.final_values
        for seg in path:
            if isinstance(cur, dict) and seg in cur:
                cur = cur[seg]
            else:
                return depth
        return cur

    def _subst(self, node, tpl):
        if isinstance(node, dict):
            return {k: self._subst(v, tpl) for k, v in node.items()}
        if isinstance(node, list):
            return [self._subst(v, tpl) for v in node]
        if isinstance(node, str):
            m = PLACEHOLDER.fullmatch(node)
            if m:
                path = m.group(1).split(".")
                got = self._resolve_and_check(path, tpl)
                return copy.deepcopy(got)
            if "{{" in node or "}}" in node:
                raise RenderError("malformed placeholder in template " + tpl)
            return node
        return node

    def _resolve_and_check(self, segs, tpl):
        cur = self.final_values
        for seg in segs:
            if isinstance(cur, dict) and seg in cur:
                cur = cur[seg]
            else:
                raise RenderError("missing value path ." + ".".join(segs) + " in template " + tpl)
        return cur

    def _key_of(self, item, key_segs, tpl, path):
        if not isinstance(item, dict):
            raise RenderError("merge-by-key item has no key " + ".".join(key_segs) + " in " + tpl + " at " + path)
        cur = item
        for seg in key_segs:
            if isinstance(cur, dict) and seg in cur:
                cur = cur[seg]
            else:
                raise RenderError("merge-by-key item has no key " + ".".join(key_segs) + " in " + tpl + " at " + path)
        return cur

    def _merge_by_key(self, base, overlay, key_segs, tpl, path):
        result = []
        target_pos = {}
        for it in base:
            k = self._key_of(it, key_segs, tpl, path)
            if k in target_pos:
                result.append(it)
            else:
                target_pos[k] = len(result)
                result.append(it)
        for it in overlay:
            k = self._key_of(it, key_segs, tpl, path)
            if k in target_pos:
                result[target_pos[k]] = deep_merge(result[target_pos[k]], it)
            else:
                target_pos[k] = len(result)
                result.append(it)
        return result

    def _navigate(self, resource, segs):
        cur = resource
        for seg in segs:
            if isinstance(cur, dict) and seg in cur:
                cur = cur[seg]
            else:
                return _MISSING  # noqa: F821
        return cur

    def _set_path(self, resource, segs, value):
        cur = resource
        for seg in segs[:-1]:
            nxt = cur.get(seg)
            if not isinstance(nxt, dict):
                nxt = {}
                cur[seg] = nxt
            cur = nxt
        cur[segs[-1]] = value

    def _apply_strategy(self, resource, tpl):
        for path, desc in self.strategy.get(tpl, {}).items():
            segs = path.split(".")
            cur = self._navigate(resource, segs)
            if cur is not _MISSING and not isinstance(cur, list):
                raise RenderError("merge target at " + path + " in " + tpl + " is not a list")
            base = cur if cur is not _MISSING else []
            ov = self._resolve(desc["from"].split("."), _MISSING)
            if ov is _MISSING:
                overlay = []
            elif not isinstance(ov, list):
                raise RenderError("merge value at " + desc["from"] + " for " + tpl + " at " + path + " is not a list")
            else:
                overlay = ov
            policy = desc["policy"]
            if policy == "replace":
                result = overlay
            elif policy == "append":
                result = base + overlay
            else:
                result = self._merge_by_key(base, overlay, desc["key"].split("."), tpl, path)
            self._set_path(resource, segs, result)

    def render(self):
        tpl_files = sorted(
            f for f in os.listdir(self.templates_dir) if f.endswith(".json")
        )
        out_plan = []  # list of (filename, resource)
        for f in tpl_files:
            tpl = f[:-5]
            doc = read_json(os.path.join(self.templates_dir, f), RenderError, "template")
            if isinstance(doc, dict):
                resources = [doc]
            elif isinstance(doc, list) and all(isinstance(e, dict) for e in doc):
                resources = doc
            else:
                raise RenderError("template " + f + " must be a JSON object or array of objects")
            rendered = []
            for res in resources:
                r = self._subst(res, f)
                self._apply_strategy(r, tpl)
                rendered.append(r)
            if len(rendered) == 1 and isinstance(doc, dict):
                out_plan.append((tpl + ".json", rendered[0]))
            else:
                width = len(str(len(rendered)))
                for i, r in enumerate(rendered):
                    out_plan.append((tpl + "-" + str(i).zfill(width) + ".json", r))
        return out_plan

    def emit(self, out_dir):
        if os.path.exists(out_dir):
            for entry in os.listdir(out_dir):
                p = os.path.join(out_dir, entry)
                if os.path.isdir(p) and not os.path.islink(p):
                    shutil.rmtree(p)
                else:
                    os.remove(p)
        else:
            os.makedirs(out_dir)
        for fname, res in self.render():
            with open(os.path.join(out_dir, fname), "w", encoding="utf-8") as fh:
                fh.write(json.dumps(res, sort_keys=True, indent=2) + "\n")


_MISSING = object()


def main(argv):
    chart_dir = None
    values_files = []
    out_dir = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--values":
            i += 1
            if i >= len(argv):
                raise UsageError("--values requires a file argument")
            values_files.append(argv[i])
        elif a.startswith("--values="):
            values_files.append(a[len("--values="):])
        elif a == "--out":
            i += 1
            if i >= len(argv):
                raise UsageError("--out requires a directory argument")
            out_dir = argv[i]
        elif a.startswith("--out="):
            out_dir = a[len("--out="):]
        elif a.startswith("--"):
            raise UsageError("unknown option " + a)
        else:
            if chart_dir is None:
                chart_dir = a
            else:
                raise UsageError("unexpected argument " + a)
        i += 1
    if chart_dir is None:
        raise UsageError("missing chart directory")
    if out_dir is None:
        raise UsageError("missing --out")
    eng = Engine(chart_dir, values_files)
    eng.emit(out_dir)
    return 0


if __name__ == "__main__":
    try:
        rc = main(sys.argv[1:])
        sys.exit(rc)
    except UsageError as exc:
        sys.stderr.write("usage error: %s\n" % exc)
        sys.exit(2)
    except ChartError as exc:
        sys.stderr.write("chart error: %s\n" % exc)
        sys.exit(3)
    except RenderError as exc:
        sys.stderr.write("render error: %s\n" % exc)
        sys.exit(4)
PYEOF

chmod +x /app/render_chart.py

# Produce the visible deliverable exactly as documented.
cd /app || exit 1
python3 /app/render_chart.py /app/charts/acme-web \
    --values /app/overrides/prod.json --values /app/overrides/edge.json \
    --out /app/rendered

echo "ember-spire oracle complete:"
ls -1 /app/rendered
