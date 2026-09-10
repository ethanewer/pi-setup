#!/usr/bin/env python3
"""yoke-lattice: a minimal, self-contained local GitHub Actions runner.

Parses a workflow YAML, topologically orders its jobs by `needs:`, runs each
job's steps in a clean `bash` per step, honours `if:` expressions (job- and
step-level), computes job `outputs:`, and writes per-job working directories
plus a machine-readable `<rundir>/summary.json`.

This is the reference solver for the yoke-lattice task. It must not read
/tests and never hardcodes any grader fixture.
"""

import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

# --------------------------------------------------------------------------
# Exit codes (part of the documented contract)
# --------------------------------------------------------------------------
EXIT_OK = 0
EXIT_USAGE = 1
EXIT_VALIDATION = 2
EXIT_CYCLE = 3
EXIT_EXPRESSION = 4

DEFAULT_REF = "refs/heads/main"
DEFAULT_EVENT = "push"
DEFAULT_SHA = "0" * 40

# Keys honoured (or explicitly ignored) at each level.
TOP_IGNORED = {"name", "on", "run-name", "permissions", "concurrency",
               "env", "defaults"}
JOB_ALLOWED = {"name", "needs", "if", "outputs", "steps", "runs-on",
               "timeout-minutes", "permissions", "concurrency", "strategy",
               "env", "container"}
STEP_ALLOWED = {"id", "name", "if", "run", "env"}


class RunnerError(Exception):
    """A fatal runner-level error: pipeline aborted, no summary written."""


# --------------------------------------------------------------------------
# Expression language (documented subset of GitHub expression syntax)
# --------------------------------------------------------------------------
class Tok:
    def __init__(self, kind, value, pos):
        self.kind = kind  # 'num','str','word','op','lparen','rparen','comma','qq','colon'
        self.value = value
        self.pos = pos

    def __repr__(self):  # pragma: no cover
        return "Tok(%s,%r)" % (self.kind, self.value)


_NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")
_WORD_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_.-]*")
_OPS = ("==", "!=", "<=", ">=", "&&", "||", "<", ">", "!", "?")


def lex(src):
    toks, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "(":
            toks.append(Tok("lparen", "(", i)); i += 1; continue
        if c == ")":
            toks.append(Tok("rparen", ")", i)); i += 1; continue
        if c == ",":
            toks.append(Tok("comma", ",", i)); i += 1; continue
        if c == ":":
            toks.append(Tok("colon", ":", i)); i += 1; continue
        if c == "'":
            j = i + 1
            buf = []
            while True:
                if j >= n:
                    raise RunnerError("unterminated single-quoted string "
                                      "at %d" % i)
                if src[j] == "'":
                    if j + 1 < n and src[j + 1] == "'":
                        buf.append("'")
                        j += 2
                        continue
                    j += 1
                    break
                buf.append(src[j])
                j += 1
            toks.append(Tok("str", "".join(buf), i))
            i = j
            continue
        if c == '"':
            j = i + 1
            buf = []
            while True:
                if j >= n:
                    raise RunnerError("unterminated double-quoted string "
                                      "at %d" % i)
                ch = src[j]
                if ch == "\\" and j + 1 < n and src[j + 1] in '"\\nrt':
                    esc = {"n": "\n", "r": "\r", "t": "\t"}.get(src[j + 1],
                                                                src[j + 1])
                    buf.append(esc)
                    j += 2
                    continue
                if ch == '"':
                    j += 1
                    break
                buf.append(ch)
                j += 1
            toks.append(Tok("str", "".join(buf), i))
            i = j
            continue
        for op in _OPS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, i))
                i += len(op)
                break
        else:
            m = _NUM_RE.match(src, i)
            if m and (i == 0 or src[i - 1] not in "A-Za-z0-9_"):
                toks.append(Tok("num", m.group(0), i))
                i = m.end()
                continue
            m = _WORD_RE.match(src, i)
            if m:
                toks.append(Tok("word", m.group(0), i))
                i = m.end()
                continue
            raise RunnerError("cannot tokenize %r at offset %d" % (src[i:], i))
    toks.append(Tok("eof", "", n))
    return toks


_TRUE = {"true", "True", "TRUE"}
_FALSE = {"false", "False", "FALSE"}
_NULL = {"null", "Null", "NULL"}


def truthy(v):
    if isinstance(v, bool):
        return v
    if v is None:
        return False
    if isinstance(v, (int, float)):
        return v != 0
    if isinstance(v, str):
        return v != ""
    return bool(v)


class Parser:
    def __init__(self, toks):
        self.toks = toks
        self.i = 0

    def peek(self):
        return self.toks[self.i]

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def parse(self):
        node = self.ternary()
        t = self.peek()
        if t.kind != "eof":
            raise RunnerError("trailing tokens at %d" % t.pos)
        return node

    def ternary(self):
        cond = self.orelse()
        if self.peek().kind == "op" and self.peek().value == "?":
            self.next()
            a = self.ternary()
            t = self.next()
            if not (t.kind == "colon"):
                raise RunnerError("expected ':' at %d" % t.pos)
            b = self.ternary()
            return ("ternary", cond, a, b)
        return cond

    def orelse(self):
        node = self.andexpr()
        while self.peek().kind == "op" and self.peek().value == "||":
            self.next()
            node = ("or", node, self.andexpr())
        return node

    def andexpr(self):
        node = self.eq()
        while self.peek().kind == "op" and self.peek().value == "&&":
            self.next()
            node = ("and", node, self.eq())
        return node

    def eq(self):
        node = self.rel()
        while self.peek().kind == "op" and self.peek().value in ("==", "!="):
            op = self.next().value
            node = (op, node, self.rel())
        return node

    def rel(self):
        node = self.unary()
        while self.peek().kind == "op" and self.peek().value in ("<", "<=",
                                                                 ">", ">="):
            op = self.next().value
            node = (op, node, self.unary())
        return node

    def unary(self):
        if self.peek().kind == "op" and self.peek().value == "!":
            self.next()
            return ("not", self.unary())
        return self.primary()

    def primary(self):
        t = self.peek()
        if t.kind == "num":
            self.next()
            return ("lit", float(t.value) if "." in t.value else int(t.value))
        if t.kind == "str":
            self.next()
            return ("lit", t.value)
        if t.kind == "word":
            if t.value in _TRUE:
                self.next()
                return ("lit", True)
            if t.value in _FALSE:
                self.next()
                return ("lit", False)
            if t.value in _NULL:
                self.next()
                return ("lit", None)
            self.next()
            name = t.value
            if self.peek().kind == "lparen":
                self.next()
                args = []
                if not (self.peek().kind == "rparen"):
                    while True:
                        args.append(self.ternary())
                        if self.peek().kind == "comma":
                            self.next()
                            continue
                        break
                t2 = self.next()
                if t2.kind != "rparen":
                    raise RunnerError("expected ')' at %d" % t2.pos)
                return ("call", name, args)
            return ("path", name)
        if t.kind == "lparen":
            self.next()
            node = self.ternary()
            t2 = self.next()
            if t2.kind != "rparen":
                raise RunnerError("expected ')' at %d" % t2.pos)
            return node
        raise RunnerError("unexpected token %r at %d" % (t.value, t.pos))


class Env:
    """Evaluation context for if-expressions / outputs."""

    def __init__(self, needs_results=None, needs_outputs=None, github=None):
        self.needs_results = needs_results or {}
        self.needs_outputs = needs_outputs or {}
        self.github = github or {}


def _num(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v)


def _str(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return ""
    return str(v)


def call_func(name, args, node_state):
    if name == "success":
        if args:
            raise RunnerError("success() takes no arguments")
        return node_state.success()
    if name == "failure":
        if args:
            raise RunnerError("failure() takes no arguments")
        return node_state.failure()
    if name == "always":
        if args:
            raise RunnerError("always() takes no arguments")
        return True
    if name == "cancelled":
        if args:
            raise RunnerError("cancelled() takes no arguments")
        return False
    if name == "contains":
        if len(args) != 2:
            raise RunnerError("contains() takes 2 arguments")
        return contains(args[0], args[1], node_state)
    if name == "startsWith":
        if len(args) != 2:
            raise RunnerError("startsWith() takes 2 arguments")
        s = args[0]
        p = args[1]
        if not isinstance(s, str) or not isinstance(p, str):
            return False
        return s.startswith(p)
    if name == "endsWith":
        if len(args) != 2:
            raise RunnerError("endsWith() takes 2 arguments")
        s = args[0]
        p = args[1]
        if not isinstance(s, str) or not isinstance(p, str):
            return False
        return s.endswith(p)
    raise RunnerError("unknown function %r" % name)


def contains(haystack, needle, node_state):
    if isinstance(haystack, list):
        for item in haystack:
            if item == needle:
                return True
        return False
    if not isinstance(haystack, str):
        return False
    if needle is None:
        return False
    return str(needle) in haystack


def resolve(path, node_env):
    """path: dotted name; supports needs.<id>.result|outputs.<k> and github.*"""
    parts = path.split(".")
    if parts[0] == "needs":
        if len(parts) == 3 and parts[2] == "result":
            return node_env.needs_results.get(parts[1])
        if len(parts) == 4 and parts[2] == "outputs":
            outs = node_env.needs_outputs.get(parts[1])
            if outs is None:
                return None
            return outs.get(parts[3])
        return None
    if parts[0] == "github":
        return node_env.github.get(parts[1]) if len(parts) == 2 else None
    return None


def evaluate(node, node_env, node_state):
    kind = node[0]
    if kind == "lit":
        return node[1]
    if kind == "path":
        return resolve(node[1], node_env)
    if kind == "call":
        args = [evaluate(a, node_env, node_state) for a in node[2]]
        return call_func(node[1], args, node_state)
    if kind == "not":
        return not truthy(evaluate(node[1], node_env, node_state))
    if kind == "and":
        l = evaluate(node[1], node_env, node_state)
        if not truthy(l):
            return False
        return truthy(evaluate(node[2], node_env, node_state))
    if kind == "or":
        l = evaluate(node[1], node_env, node_state)
        if truthy(l):
            return True
        return truthy(evaluate(node[2], node_env, node_state))
    if kind in ("==", "!=", "<", "<=", ">", ">="):
        l = evaluate(node[1], node_env, node_state)
        r = evaluate(node[2], node_env, node_state)
        if kind in ("==", "!="):
            eq = (l == r)
            return eq if kind == "==" else (not eq)
        ln, rn = _num(l), _num(r)
        if ln is None or rn is None:
            return False
        return {"<": ln < rn, "<=": ln <= rn,
                ">": ln > rn, ">=": ln >= rn}[kind]
    if kind == "ternary":
        cond = evaluate(node[1], node_env, node_state)
        if truthy(cond):
            return evaluate(node[2], node_env, node_state)
        return evaluate(node[3], node_env, node_state)
    raise RunnerError("internal: unknown node %r" % (kind,))


def parse_expr(text, where):
    try:
        p = Parser(lex(text))
        return p.parse()
    except RunnerError as e:
        raise RunnerError("%s: bad expression %r: %s" % (where, text, e))


# --------------------------------------------------------------------------
# Workflow loading & topo order
# --------------------------------------------------------------------------
def load_workflow(path):
    if yaml is None:
        raise RunnerError("PyYAML is not installed")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except OSError as e:
        raise RunnerError("cannot read workflow %s: %s" % (path, e))
    except yaml.YAMLError as e:
        raise RunnerError("workflow %s is not valid YAML: %s" % (path, e))
    if not isinstance(data, dict) or "jobs" not in data:
        raise RunnerError("workflow %s has no top-level jobs mapping" % path)
    jobs = data["jobs"]
    if not isinstance(jobs, dict) or not jobs:
        raise RunnerError("workflow %s: jobs must be a non-empty mapping" % path)
    out = {}
    for jid, spec in jobs.items():
        if not isinstance(jid, str) or not jid:
            raise RunnerError("job id must be a non-empty string")
        if not isinstance(spec, dict):
            raise RunnerError("job %r must be a mapping" % jid)
        for key in spec:
            if key not in JOB_ALLOWED:
                raise RunnerError("job %r: unsupported key %r" % (jid, key))
        if "steps" not in spec:
            raise RunnerError("job %r has no steps" % jid)
        if not isinstance(spec["steps"], list):
            raise RunnerError("job %r steps must be a list" % jid)
        needs = spec.get("needs", [])
        if isinstance(needs, str):
            needs = [needs]
        if not isinstance(needs, list) or not all(
                isinstance(n, str) for n in needs):
            raise RunnerError("job %r needs must be a string or a list of "
                              "strings" % jid)
        if len(set(needs)) != len(needs):
            raise RunnerError("job %r has duplicate needs entries" % jid)
        if "if" in spec and isinstance(spec["if"], bool):
            spec["if"] = "true" if spec["if"] else "false"
        steps = []
        for idx, st in enumerate(spec["steps"], 1):
            if not isinstance(st, dict):
                raise RunnerError("job %r step %d must be a mapping" % (jid, idx))
            for key in st:
                if key not in STEP_ALLOWED:
                    raise RunnerError("job %r step %d: unsupported key %r"
                                      % (jid, idx, key))
            if "run" not in st:
                raise RunnerError("job %r step %d has no run" % (jid, idx))
            if not isinstance(st["run"], str):
                raise RunnerError("job %r step %d run must be a string"
                                  % (jid, idx))
            for k in ("id", "name", "if"):
                if k in st and not isinstance(st[k], (str, bool)):
                    raise RunnerError("job %r step %d %s must be a string"
                                      % (jid, idx, k))
                if k == "if" and isinstance(st.get(k), bool):
                    st[k] = "true" if st[k] else "false"
            if "env" in st:
                env = st["env"]
                if not isinstance(env, dict) or not all(
                        isinstance(k, str) for k in env):
                    raise RunnerError("job %r step %d env must be a mapping "
                                      "of strings" % (jid, idx))
                for k, v in env.items():
                    if v is None:
                        env[k] = ""
            steps.append(st)
        if "outputs" in spec:
            outs = spec["outputs"]
            if not isinstance(outs, dict) or not all(
                    isinstance(k, str) for k in outs):
                raise RunnerError("job %r outputs must be a mapping" % jid)
        else:
            outs = None
        out[jid] = {
            "needs": needs,
            "if": spec.get("if"),
            "outputs": outs,
            "steps": steps,
            "order": spec.get("name"),
        }
    for jid, j in out.items():
        for n in j["needs"]:
            if n not in out:
                raise RunnerError("job %r needs unknown job %r" % (jid, n))
    return out


def topo_order(jobs):
    order = []
    done = set()
    pending = list(jobs)          # declaration order
    while pending:
        advanced = False
        for jid in list(pending):
            if all(n in done for n in jobs[jid]["needs"]):
                order.append(jid)
                done.add(jid)
                pending.remove(jid)
                advanced = True
        if not advanced:
            raise RunnerError("dependency cycle among jobs: %s" % pending)
    return order


# --------------------------------------------------------------------------
# Pipeline execution
# --------------------------------------------------------------------------
class NodeState:
    """success()/failure() semantics for one evaluation point."""

    def __init__(self, fail=False, needs_failed=False):
        self.fail = fail
        self.needs_failed = needs_failed

    def success(self):
        return not self.fail and not self.needs_failed

    def failure(self):
        return self.fail or self.needs_failed

    def __repr__(self):  # pragma: no cover
        return "NodeState(fail=%r, needs_failed=%r)" % (
            self.fail, self.needs_failed)


def eval_text(text, node_state, env, where):
    if not isinstance(text, str):
        text = str(text)
    tree = parse_expr(text, where)
    val = evaluate(tree, env, node_state)
    return truthy(val)


def run_workflow(workflow_path, rundir, workspace, ref, event, sha):
    jobs = load_workflow(workflow_path)
    order = topo_order(jobs)

    rundir = os.path.abspath(rundir)
    jobs_root = os.path.join(rundir, "jobs")
    logs_root = os.path.join(rundir, "logs")
    for p in (jobs_root, logs_root):
        if os.path.isdir(p):
            import shutil
            shutil.rmtree(p)
        os.makedirs(p, exist_ok=True)

    github = {"ref": ref, "event_name": event, "sha": sha}
    statuses = {}   # job id -> 'success'|'failure'|'skipped'
    outputs = {}    # job id -> dict (only for success)

    needs_failed_cache = {}

    def node_env_for(jid, needs_scope):
        """Build the context Env; needs_scope selects which NodeState
        semantics apply (jobs consider needs results, steps do not)."""
        nr = {}
        no = {}
        for n in jobs[jid]["needs"]:
            nr[n] = statuses.get(n, "skipped")
            no[n] = outputs.get(n, {})
        if jid not in needs_failed_cache:
            needs_failed_cache[jid] = any(
                statuses.get(n, "skipped") != "success"
                for n in jobs[jid]["needs"])
        return Env(nr, no, github), needs_failed_cache[jid]

    summary_jobs = {}
    for jid in order:
        job = jobs[jid]
        env, needs_failed = node_env_for(jid, True)
        st0 = NodeState(fail=False, needs_failed=needs_failed)
        if_text = job["if"] if job["if"] is not None else "success()"
        cond = eval_text(if_text, st0, env, "job %s if" % jid)
        if not cond:
            reason = ("needs" if any(
                statuses.get(n, "skipped") != "success"
                for n in job["needs"]) else "if")
            statuses[jid] = "skipped"
            summary_jobs[jid] = {
                "needs": list(job["needs"]),
                "status": "skipped",
                "skip_reason": reason,
                "outputs": {},
                "steps": [],
            }
            continue

        job_dir = os.path.join(jobs_root, jid)
        os.makedirs(job_dir, exist_ok=True)
        failed = False
        steps_out = []
        for idx, st in enumerate(job["steps"], 1):
            env, _ = node_env_for(jid, False)
            # Step scope: success()/failure() refer only to this job's own
            # prior steps, never to needs results (GitHub semantics).
            st_step = NodeState(fail=failed, needs_failed=False)
            step_if = st.get("if") if st.get("if") is not None else "success()"
            step_cond = eval_text(step_if, st_step, env,
                                  "job %s step %d if" % (jid, idx))
            if not step_cond:
                steps_out.append({
                    "index": idx,
                    "id": st.get("id"),
                    "name": st.get("name"),
                    "status": "skipped",
                    "exit_code": None,
                })
                continue
            slug = re.sub(r"[^A-Za-z0-9]+", "-", (st.get("id") or
                                                  st.get("name") or
                                                  "%d" % idx)).strip("-")
            log_path = os.path.join(logs_root, jid,
                                    "step-%02d-%s.log" % (idx, slug or "step"))
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            env = dict(os.environ)
            env.update({
                "GITHUB_WORKSPACE": workspace,
                "GITHUB_JOB": jid,
                "GITHUB_REF": ref,
                "GITHUB_EVENT_NAME": event,
                "GITHUB_SHA": sha,
            })
            if st.get("env"):
                for k, v in st["env"].items():
                    env[str(k)] = str(v)
            with open(log_path, "wb") as lf:
                try:
                    r = subprocess.run(
                        ["bash", "--noprofile", "--norc", "-eo", "pipefail",
                         "-c", st["run"]],
                        cwd=job_dir, env=env, stdout=lf, stderr=subprocess.STDOUT)
                except OSError as e:  # pragma: no cover
                    raise RunnerError("cannot spawn bash: %s" % e)
            code = r.returncode
            if code == 0:
                steps_out.append({
                    "index": idx,
                    "id": st.get("id"),
                    "name": st.get("name"),
                    "status": "success",
                    "exit_code": 0,
                })
            else:
                failed = True
                steps_out.append({
                    "index": idx,
                    "id": st.get("id"),
                    "name": st.get("name"),
                    "status": "failure",
                    "exit_code": code,
                })
        status = "failure" if failed else "success"
        statuses[jid] = status
        outs = {}
        if status == "success" and job["outputs"]:
            env, _ = node_env_for(jid, False)
            st_out = NodeState(fail=False, needs_failed=False)
            for k, expr in job["outputs"].items():
                tree = parse_expr(str(expr), "job %s output %s" % (jid, k))
                val = evaluate(tree, env, st_out)
                outs[k] = val
            outputs[jid] = outs
        summary_jobs[jid] = {
            "needs": list(job["needs"]),
            "status": status,
            "skip_reason": None,
            "outputs": outs,
            "steps": steps_out,
        }

    summary = {
        "workflow": os.path.basename(workflow_path),
        "order": order,
        "jobs": summary_jobs,
    }
    with open(os.path.join(rundir, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, sort_keys=True)
    return summary


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def usage():
    sys.stderr.write(
        "usage: %s <workflow.yml> <rundir> [--workspace DIR] "
        "[--ref REF] [--event EVENT] [--sha SHA]\n" % sys.argv[0])
    return EXIT_USAGE


def main(argv):
    args = list(argv)
    if len(args) < 2:
        return usage()
    workflow, rundir = args[0], args[1]
    workspace, ref, event, sha = (os.path.dirname(os.path.abspath(workflow)),
                                  DEFAULT_REF, DEFAULT_EVENT, DEFAULT_SHA)
    i = 2
    while i < len(args):
        a = args[i]
        if a == "--workspace" and i + 1 < len(args):
            workspace = args[i + 1]
            i += 2
        elif a == "--ref" and i + 1 < len(args):
            ref = args[i + 1]
            i += 2
        elif a == "--event" and i + 1 < len(args):
            event = args[i + 1]
            i += 2
        elif a == "--sha" and i + 1 < len(args):
            sha = args[i + 1]
            i += 2
        else:
            return usage()
    if not os.path.isfile(workflow):
        sys.stderr.write("workflow file not found: %s\n" % workflow)
        return EXIT_VALIDATION
    if not os.path.isdir(workspace):
        sys.stderr.write("workspace is not a directory: %s\n" % workspace)
        return EXIT_VALIDATION
    try:
        run_workflow(workflow, rundir, workspace, ref, event, sha)
    except RunnerError as e:
        sys.stderr.write("runner error: %s\n" % e)
        return EXIT_EXPRESSION if "expression" in str(e) or "unknown function" in str(e) else (
            EXIT_CYCLE if "cycle" in str(e) else EXIT_VALIDATION)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))