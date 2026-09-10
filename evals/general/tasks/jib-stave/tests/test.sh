#!/usr/bin/env bash
# Verifier for jib-stave (executes-deliverable).
#
# Drives the full release-pipeline acceptance sequence inside /app and asserts
# the outcome contract: npm ci from the committed lockfile, one build emitting
# declarations for all three packages, per-package suites green, visible and
# hidden downstream consumers type-checking against the published packages,
# emitted .d.ts contents current (2.1.0 API, no 1.4-era surface), published
# entrypoints pointing at build output, and manifest version metadata exactly
# on the 2.1.0 line.
#
# Guarantee a reward on every exit path. Without this a verifier that raises
# while inspecting the agent's deliverable writes nothing at all, which yields
# a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

cd /app || { echo "0" > /logs/verifier/reward.txt; exit 0; }
. ~/.nvm/nvm.sh >/dev/null 2>&1 || true

python3 - <<'PY'
import os
import re
import shutil
import subprocess
import sys

ROOT = "/app"
REWARD = "/logs/verifier/reward.txt"
failures = []


def fail(msg: str) -> None:
    failures.append(msg)
    print("FAIL:", msg, flush=True)


def run(args, *, cwd=ROOT, timeout=420):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                          timeout=timeout)


def run_ok(args, *, cwd=ROOT, label, timeout=420):
    r = run(args, cwd=cwd, timeout=timeout)
    if r.returncode != 0:
        tail = (r.stdout or "")[-1500:] + (r.stderr or "")[-1500:]
        fail("%s (rc=%d): %s" % (label, r.returncode, tail[-1200:]))
        return False
    return True


# ------------------------------------------------------------------
# 0. the declared deliverables must exist (the manifests are data; the
#    declaration file is produced by the build we run in step 2)
# ------------------------------------------------------------------
for d in [
    "/app/package.json",
    "/app/packages/core/package.json",
    "/app/packages/scale/package.json",
    "/app/packages/api/package.json",
]:
    if not os.path.isfile(d):
        fail("missing deliverable %s" % d)

# ------------------------------------------------------------------
# 1. npm ci from the committed lockfile, cache-only
# ------------------------------------------------------------------
if run_ok(["npm", "ci", "--offline", "--no-audit", "--no-fund",
           "--loglevel=error"], label="npm ci --offline"):
    print("ok: npm ci --offline", flush=True)

# ------------------------------------------------------------------
# 2. one build, declarations for all three packages
# ------------------------------------------------------------------
# Every build-output artifact must be produced by the build we drive below;
# anything the agent left behind (dist/, tsbuildinfo) is removed first so
# pre-placed output cannot survive into the checks.
for pkg in ["core", "scale", "api"]:
    shutil.rmtree(ROOT + "/packages/%s/dist" % pkg, ignore_errors=True)
    tb = ROOT + "/packages/%s/tsconfig.tsbuildinfo" % pkg
    if os.path.exists(tb):
        os.unlink(tb)
if run_ok(["npm", "run", "build", "-ws"], label="npm run build -ws"):
    print("ok: npm run build -ws", flush=True)

# ------------------------------------------------------------------
# 3. per-package suites are green against the built output
# ------------------------------------------------------------------
# The suites themselves are part of the shipped environment: a repaired
# workspace must leave them untouched. Byte-compare against the canonical
# copies so neutered or replaced runtime checks cannot pass.
SUITE_FIXT = "/tests/suite-fixtures"
for pkg_, rel in [("core", "core/token.test.ts"),
                  ("scale", "scale/assess.test.ts"),
                  ("api", "api/client.test.ts")]:
    canon = SUITE_FIXT + "/" + rel
    if not os.path.isfile(canon):
        fail("suite fixture %s missing (verifier packaging error)" % canon)
        continue
    try:
        with open(canon, "rb") as cf, open("/app/packages/%s/test/%s"
                                           % (pkg_, rel.split("/")[1]),
                                           "rb") as sf:
            if cf.read() != sf.read():
                fail("%s test suite differs from the shipped suite" % pkg_)
    except OSError as e:
        fail("cannot compare %s test suite: %s" % (pkg_, e))
# the shipped consumer fixture is read-only evidence; it must not be edited
for rel in ["consumer.ts", "tsconfig.json"]:
    try:
        with open(SUITE_FIXT + "/consumer/" + rel, "rb") as cf, \
             open(ROOT + "/consumer/" + rel, "rb") as sf:
            if cf.read() != sf.read():
                fail("consumer/%s differs from the shipped fixture" % rel)
    except OSError as e:
        fail("cannot compare consumer/%s: %s" % (rel, e))
if run_ok(["npm", "test", "-ws"], label="npm test -ws"):
    print("ok: npm test -ws", flush=True)

# ------------------------------------------------------------------
# 4. visible consumer compiles against the published packages
# ------------------------------------------------------------------
TSC = ROOT + "/node_modules/.bin/tsc"
if os.path.isfile(TSC):
    if run_ok([TSC, "-p", ROOT + "/consumer/tsconfig.json"],
              label="tsc consumer (visible)"):
        print("ok: visible consumer compiles", flush=True)
else:
    fail("tsc binary missing after npm ci: %s" % TSC)

# ------------------------------------------------------------------
# 5. hidden consumers: copied into the workspace, compiled through the
#    published packages, plus per-case declaration-content asserts
# ------------------------------------------------------------------
hidden = ["h1", "h2"]
for case in hidden:
    src = "/tests/hidden/%s" % case
    dst = ROOT + "/.consumers/%s" % case
    if not os.path.isdir(src):
        fail("hidden fixture %s missing" % src)
        continue
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(src):
        shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
    if not run_ok([TSC, "-p", dst + "/tsconfig.json"],
                  label="tsc consumer %s (hidden)" % case):
        continue
    print("ok: hidden consumer %s compiles" % case, flush=True)

# ------------------------------------------------------------------
# 6. emitted declaration contents (current API, no 1.4-era surface)
# ------------------------------------------------------------------
def text(p: str) -> str:
    try:
        return open(p, "r", encoding="utf-8").read()
    except OSError:
        fail("cannot read emitted declaration %s" % p)
        return ""

core_dts = text("/app/packages/core/dist/index.d.ts")
scale_dts = text("/app/packages/scale/dist/index.d.ts")
api_dts = text("/app/packages/api/dist/index.d.ts")

for token in ["issue", "verify", "TokenKind", "checksum", "nonce"]:
    if token not in core_dts:
        fail('core dist/index.d.ts missing current API token %r' % token)
for token in ["mint", "validate", "expiresAt"]:
    if token in core_dts:
        fail('core dist/index.d.ts still exposes 1.4-era token %r' % token)

if '"@jibblin/core"' not in scale_dts:
    fail('scale dist/index.d.ts does not import @jibblin/core by package name')
if "assess" not in scale_dts or "reify" not in scale_dts:
    fail('scale dist/index.d.ts missing assessment exports')
if "../core" in scale_dts or "../packages" in scale_dts:
    fail('scale dist/index.d.ts contains relative workspace paths')

if '"@jibblin/scale"' not in api_dts:
    fail('api dist/index.d.ts does not import @jibblin/scale by package name')
if "export declare class Client" not in api_dts:
    fail('api dist/index.d.ts missing Client class')
for token in ["mint", "expiresAt"]:
    if token in api_dts:
        fail('api dist/index.d.ts leaks 1.4-era token %r' % token)

# ------------------------------------------------------------------
# 7. no stale packaged artifacts shadow the build output
# ------------------------------------------------------------------
if os.path.exists("/app/packages/core/lib"):
    fail("stale packaged artifact /app/packages/core/lib still present")

# ------------------------------------------------------------------
# 8. published entrypoints point at each package's own build output
# ------------------------------------------------------------------
def read_json(p: str):
    try:
        import json
        return json.load(open(p))
    except Exception as e:
        fail("cannot parse %s: %s" % (p, e))
        return None

for pkg, name in [("core", "@jibblin/core"), ("scale", "@jibblin/scale"),
                  ("api", "@jibblin/api")]:
    man = read_json("/app/packages/%s/package.json" % pkg)
    if man is None:
        continue
    if not man.get("main", "").endswith("dist/index.js"):
        fail("%s main does not point at build output" % name)
    if not man.get("types", "").endswith("dist/index.d.ts"):
        fail("%s types does not point at build output" % name)
    ex = man.get("exports", {}).get(".", {})
    if not isinstance(ex, dict) or ex.get("types") != "./dist/index.d.ts":
        fail("%s exports[\".\"].types is not ./dist/index.d.ts" % name)

# ------------------------------------------------------------------
# 9. version metadata: exactly the 2.1.0 line, single resolved instance
# ------------------------------------------------------------------
core_man = read_json("/app/packages/core/package.json")
scale_man = read_json("/app/packages/scale/package.json")
api_man = read_json("/app/packages/api/package.json")

for name, man in [("core", core_man), ("scale", scale_man), ("api", api_man)]:
    if man is not None and man.get("version") != "2.1.0":
        fail("%s package.json version is %r, expected 2.1.0"
             % (name, man.get("version")))
    if man is not None and man.get("scripts", {}).get("test") != "node --test":
        fail("%s scripts.test is %r, expected \"node --test\""
             % (name, man.get("scripts", {}).get("test")))

if api_man is not None:
    deps = api_man.get("dependencies", {})
    if deps.get("@jibblin/core") != "^2.1.0":
        fail("api pins @jibblin/core to %r, expected ^2.1.0"
             % deps.get("@jibblin/core"))
    if deps.get("@jibblin/scale") != "^2.1.0":
        fail("api pins @jibblin/scale to %r, expected ^2.1.0"
             % deps.get("@jibblin/scale"))
if scale_man is not None:
    deps = scale_man.get("dependencies", {})
    if deps.get("@jibblin/core") != "^2.1.0":
        fail("scale pins @jibblin/core to %r, expected ^2.1.0"
             % deps.get("@jibblin/core"))

# installed tree: exactly one instance of each sibling, symlinked to the
# workspace, at the release line
for name in ("core", "scale", "api"):
    p = "/app/node_modules/@jibblin/%s" % name
    if not os.path.islink(p):
        fail("/app/node_modules/@jibblin/%s is not a workspace symlink" % name)
        continue
    man = read_json(p + "/package.json")
    if man is not None and man.get("version") != "2.1.0":
        fail("installed @jibblin/%s resolves to %r, expected 2.1.0"
             % (name, man.get("version")))

# ------------------------------------------------------------------
# reward: binary, written last
# ------------------------------------------------------------------
print("failures=%d" % len(failures), flush=True)
if failures:
    print("jib-stave verifier: NOT green", flush=True)
    with open(REWARD, "w") as fh:
        fh.write("0")
else:
    print("jib-stave verifier: green", flush=True)
    with open(REWARD, "w") as fh:
        fh.write("1")
sys.exit(0)
PY