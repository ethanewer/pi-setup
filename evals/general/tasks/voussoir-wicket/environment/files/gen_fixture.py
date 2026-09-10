#!/usr/bin/env python3
"""Deterministic fixture generator for the "voussoir-wicket" task.

Builds a disk-full host-root incident tree: a directory full of junk that must
be pruned down to a size budget, with one or more RETENTION-manifested areas
whose *contents look identical to the junk* (same suffixes, same core-dump
style names, same random-looking filenames).  A naive `find -delete` or a glob
`rm -rf` destroys the retained area; the manifest is the only authority that
distinguishes it.

The tree produced for a given --profile is byte-for-byte deterministic (fixed
seed, fixed content, fixed mtimes, fixed ownership), so the Docker build and
this authoring-time catalog run cannot drift.

Feasibility is asserted before writing anything: the budget must be reachable
by deleting junk alone, and there must be enough junk that deleting it all
lands under budget.

Usage:
  python3 gen_fixture.py --profile meridian --root /app/data
  python3 gen_fixture.py --profile meridian --root /tmp/meridian \
        --catalog /tmp/meridian-expected.json
  python3 gen_fixture.py --profile h1 --root /tmp/tree-h1

Profiles: meridian (visible), h1 / h2 / h3 (hidden generalization cases).
"""
import argparse
import datetime
import hashlib
import json
import os
import random
import stat
import sys


def ns_of(y, m, d, H, M, S):
    return int(datetime.datetime(y, m, d, H, M, S,
                                 tzinfo=datetime.timezone.utc).timestamp() * 1e9)


# Fixed timestamps (UTC).  J1/J2/J3 are junk mtimes of increasing recency;
# P0 is the "restore point" timestamp every retained file/dir carries.
J1 = ns_of(2025, 11, 4, 8, 15, 0)
J2 = ns_of(2025, 12, 9, 22, 41, 0)
J3 = ns_of(2026, 1, 1, 7, 3, 0)
P0 = ns_of(2026, 1, 2, 3, 4, 5)

MAIL_UID = 2003   # service account owning the retained areas
MAIL_GID = 2004

BLOCK = 65536


def blob(profile, rel, size):
    """Deterministic pseudo-random content, seeded per path."""
    return random.Random("%s::%s" % (profile, rel)).randbytes(size)


def sha256(b):
    return hashlib.sha256(b).hexdigest()


class Fixture:
    def __init__(self, profile, root):
        self.profile = profile
        self.root = root
        self.entries = {}       # rel -> {size, protected, mode, uid, gid, mtime_ns, sha256}
        self.protected_dirs = {}  # rel(dir) -> {mode, uid, gid, mtime_ns}
        self.policy = None

    def _write(self, rel, data, mode=0o644, protected=False,
               mtime_ns=None, chown=None, nlink_ok=True):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as fh:
            fh.write(data)
        os.chmod(p, mode)
        if mtime_ns is not None:
            os.utime(p, ns=(mtime_ns, mtime_ns))
        if chown is not None:
            try:
                os.chown(p, chown[0], chown[1])
            except OSError:
                pass  # non-root host at authoring time; catalog records intent
        ent = {
            "size": len(data),
            "protected": protected,
            "mode": stat.S_IFREG | mode,
            "uid": chown[0] if chown else os.geteuid(),
            "gid": chown[1] if chown else os.getegid(),
            "mtime_ns": mtime_ns if mtime_ns is not None else
                        os.stat(p).st_mtime_ns,
        }
        if protected:
            ent["sha256"] = sha256(data)
        self.entries[rel] = ent

    def real(self, rel, text, mode=0o644):
        self._write(rel, text.encode("utf-8"), mode=mode)

    def real_blob(self, rel, size, mode=0o644):
        self._write(rel, blob(self.profile, rel, size), mode=mode)

    def junk(self, rel, size, mtime_ns):
        self._write(rel, blob(self.profile, rel, size), mode=0o644,
                    mtime_ns=mtime_ns)

    def retained(self, rel, size, mtime_ns=P0):
        self._write(rel, blob(self.profile, rel, size), mode=0o664,
                    protected=True, mtime_ns=mtime_ns,
                    chown=(MAIL_UID, MAIL_GID))

    def protect_dirs(self, roots, mode=0o770, mtime_ns=P0):
        """Stamp every directory at/below the retained roots (deepest first)."""
        dirs = set()
        for r in roots:
            base = os.path.join(self.root, r)
            for dp, dns, fns in os.walk(base):
                dirs.add(os.path.relpath(dp, self.root))
        for rel in sorted(dirs, key=lambda x: x.count("/"), reverse=True):
            p = os.path.join(self.root, rel)
            os.chmod(p, mode)
            try:
                os.chown(p, MAIL_UID, MAIL_GID)
            except OSError:
                pass
            os.utime(p, ns=(mtime_ns, mtime_ns))
            self.protected_dirs[rel] = {
                "mode": stat.S_IFDIR | mode,
                "uid": MAIL_UID, "gid": MAIL_GID, "mtime_ns": mtime_ns,
            }

    def write_policy(self, spec):
        policy = {
            "schema": "meridian-cleanup-policy/v1",
            "host": spec["host"],
            "budget_bytes": spec["budget"],
            "retention_manifest": "RESTORE.manifest",
            "junk": spec["criteria"],
        }
        self.policy = policy
        self.real("policy.json", json.dumps(policy, indent=2) + "\n")

    def write_manifest(self, roots, date="2026-01-02"):
        self.policy["_protected_roots"] = list(roots)
        lines = [
            "# RESTORE.manifest",
            "# Generated by the meridian backup service on %s." % date,
            "# One restored path per line, relative to the host root.",
            "# Every file at or below a listed path is part of a restored tree",
            "# and MUST be preserved byte-for-byte: content, permissions,",
            "# ownership and timestamps.  The backup team owns these paths;",
            "# nothing in the cleanup policy may touch them.",
            "#",
        ]
        lines += ["%s" % r for r in roots]
        self.real("RESTORE.manifest", "\n".join(lines) + "\n")

    def write_readme(self, text):
        self.real("README.md", text)

    def sizes(self):
        orig = sum(e["size"] for e in self.entries.values())
        nonjunk = 0      # must-survive bytes: retained areas + real data
        junk_total = 0
        for rel, e in self.entries.items():
            if e["protected"]:
                nonjunk += e["size"]
            elif junk_match(rel, e["size"], self.policy):
                junk_total += e["size"]
            else:
                nonjunk += e["size"]
        return orig, nonjunk, junk_total

    def assert_feasible(self):
        orig, nonjunk, junk_total = self.sizes()
        budget = self.policy["budget_bytes"]
        margin = 512 * 1024
        if nonjunk > budget:
            raise SystemExit(
                "INFEASIBLE: non-junk size %d exceeds budget %d" %
                (nonjunk, budget))
        need = orig - budget + margin
        if junk_total < need:
            raise SystemExit(
                "INFEASIBLE: junk %d < original-budget+margin %d "
                "(orig=%d budget=%d)" % (junk_total, need, orig, budget))
        return orig, nonjunk, junk_total

    def write_catalog(self, out_path):
        catalog = {
            "generator": "gen_fixture.py",
            "profile": self.profile,
            "host": self.policy["host"],
            "budget_bytes": self.policy["budget_bytes"],
            "manifest_name": self.policy["retention_manifest"],
            "protected_roots": [r for r in (
                self.policy.get("_protected_roots") or [])],
            "files": self.entries,
            "protected_dirs": self.protected_dirs,
        }
        with open(out_path, "w") as fh:
            json.dump(catalog, fh, indent=1, sort_keys=True)
            fh.write("\n")


def junk_match(rel, size, policy):
    """True when a regular file at rel with the given size is junk per the
    machine policy.  Retained-area membership is decided by the caller."""
    j = policy["junk"]
    suffixes = j.get("suffixes", [])
    prefixes = j.get("prefixes", [])
    dir_names = j.get("dir_names", [])
    min_size = j.get("min_size_bytes", 0)
    if size < min_size:
        return False
    base = rel.rsplit("/", 1)[-1]
    if any(base.endswith(s) for s in suffixes):
        return True
    if any(base.startswith(p) for p in prefixes):
        return True
    parts = rel.split("/")
    if len(parts) > 1 and any(dn in parts[:-1] for dn in dir_names):
        return True
    return False


README_MERIDIAN = """# meridian -- shared compute & mail host

This box hosts team workspaces, project sources, shared datasets, the notify
fan-out service and the mail service.  It is a shared host: other teams look at
the tree, so do not guess -- read the documents below before touching anything.

## Layout

    teams/       per-team workspace checkouts (alpha, beta, gamma)
    projects/    one real project checkout (meridian-core)
    datasets/    shared dataset files (large, do NOT delete)
    backups/     offline backup staging (do NOT delete)
    services/    service homes (notify, mail)

## What is junk

The machine-readable cleanup policy in `policy.json` defines exactly what counts
as junk (file-name suffixes, directory names, core-dump prefixes, minimum
sizes) and the size budget this host must stay under.  Follow it precisely.

## What must NEVER be deleted

The file `RESTORE.manifest` is produced by the backup service.  Every path it
lists is a restored tree: those files are live service data, and they are
required to stay byte-for-byte identical -- content, permissions, ownership and
timestamps.  Do not delete, rewrite, chmod, chown, touch or recreate anything
at or below a listed path.  If the budget cannot be met without touching a
listed path, the policy is wrong and must be reported, not worked around.

## House rules

* Never create files inside the host root.
* The cleanup policy file and the restore manifest are part of the host
  definition; they are not junk, never remove them.
* When in doubt, read the manifest.
"""

README_H1 = """# loghost -- ingress log collector

Collects request logs from the fleet.  Layout:

    ingress/     rotated request/response logs (junk once rotated)
    app/web/tmp/ transient scratch files (junk)
    var/crash/   core dumps (junk)
    config/      service configuration (real)
    archive/     kept archive data (real)

The cleanup policy in `policy.json` defines the junk rules and the budget.
`RESTORE.manifest` lists the restored trees that must be kept byte-for-byte
(content, permissions, ownership, timestamps).  Never touch anything at or
below a listed path -- even when it lives inside a directory that otherwise
looks like junk.  Never create files in the root, and never remove the policy
or the manifest.
"""

README_H2 = """# cifarm -- CI runners & evidence vault

Runs build jobs and stores job evidence.  Layout:

    runner/workspaces/  per-job checkouts (source is real; build leftovers junk)
    runner/vault/       tamper-evident evidence store (RESTORE.manifest)
    runner/recordings/  session recordings (RESTORE.manifest)

The cleanup policy in `policy.json` defines the junk rules and the size
budget; note it applies a minimum file size, so small files are never junk.
`RESTORE.manifest` lists the restored trees that must remain byte-for-byte
identical (content, permissions, ownership, timestamps).  Never remove the
policy or the manifest, and never create files inside the root.
"""

README_H3 = """# relay-farm -- message relay & gateway services

Relays messages between fleets.  Layout:

    services/gateway/  gateway logs, caches and staging junk
    var/crash/         core dumps (junk)
    var/hold/          quarantined messages awaiting review (RESTORE.manifest)
    var/lib/           live databases (real -- keep them)
    config/            configuration (real)

The cleanup policy in `policy.json` defines the junk rules and the budget.
`RESTORE.manifest` lists the restored trees that must remain byte-for-byte
identical (content, permissions, ownership, timestamps).  Never remove the
policy or the manifest, and never create files inside the root.
"""


def build_meridian(fx):
    fx.write_policy({
        "host": "meridian",
        "budget": 12_582_912,   # 12 MiB
        "criteria": {
            "suffixes": [".tmp", ".log", ".pid", ".swp", ".pyc"],
            "dir_names": ["__pycache__", "node_modules", ".cache",
                          "scratch", "build"],
            "prefixes": ["core."],
            "min_size_bytes": 0,
        },
    })
    roots = ["services/mail/var"]
    fx.write_manifest(roots)
    fx.write_readme(README_MERIDIAN)

    # ---- real data (never junk, must survive) -------------------------------
    fx.real("teams/alpha/workspace-heron/README.md",
            "# workspace-heron\nTelemetry workspace for the heron pipeline.\n")
    fx.real("teams/alpha/workspace-heron/pyproject.toml",
            "[project]\nname = \"heron\"\nversion = \"0.4.2\"\ndeps = [\"numpy\"]\n")
    fx.real("teams/alpha/workspace-heron/src/main.py",
            "def telemetry():\n    return 41\n\nif __name__ == '__main__':\n"
            "    print(telemetry())\n")
    fx.real("teams/alpha/workspace-heron/src/render.py",
            "def render(rows):\n    return [dict(r) for r in rows]\n")
    fx.real("teams/beta/workspace-vent-2/README.md",
            "# workspace-vent-2\nDispatch service workspace.\n")
    fx.real("teams/beta/workspace-vent-2/app.js",
            "const dispatch = (q) => q.map(x => x * 2);\n"
            "module.exports = { dispatch };\n")
    fx.real("teams/beta/workspace-vent-2/config.json",
            '{"endpoint": "amqp://vent.local", "workers": 6}\n')
    fx.real("teams/gamma/docs/index.md",
            "# Gamma team docs\nOperating notes for the gamma fleet.\n")
    fx.real("teams/gamma/docs/sizing.md",
            "# Sizing\nEach node reserves 3 GiB for the dataset cache.\n")
    fx.real("teams/gamma/docs/diagram.svg",
            '<svg width="4" height="4"><rect width="4" height="4"/></svg>\n')
    fx.real("projects/meridian-core/README.md",
            "# meridian-core\nCore scheduling library.\n")
    fx.real("projects/meridian-core/pyproject.toml",
            '[project]\nname="meridian-core"\nversion="1.2.0"\n')
    fx.real("projects/meridian-core/src/meridian/__init__.py",
            'VERSION = "1.2.0"\n')
    fx.real("projects/meridian-core/src/meridian/core.py",
            "def schedule(jobs):\n    return sorted(jobs, key=lambda j: j.p)\n")
    fx.real("projects/meridian-core/src/meridian/queue.py",
            "class Queue:\n    def push(self, j):\n        self._q.append(j)\n")
    fx.real("projects/meridian-core/tests/test_core.py",
            "def test_order():\n    assert schedule([]) == []\n")
    fx.real("projects/meridian-core/tests/test_queue.py",
            "def test_push_pop():\n    q = Queue()\n    q.push(1)\n")
    fx.real("services/mail/README.md",
            "# mail service\nRuns out of var/.  Data is restored by the backup\n"
            "service; check RESTORE.manifest before touching anything.\n")
    fx.real("backups/restore-procedure.txt",
            "1. verify the manifest\n2. rsync from the vault\n3. fsck\n")
    fx.real_blob("datasets/usa-cities.json", 1_100_000)
    fx.real_blob("datasets/embeddings.bin", 900_000)
    fx.real_blob("backups/last-good.tar.gz", 1_150_000)

    # ---- retained (restore manifest) -- contents look exactly like junk ----
    for rel, size in [
        ("services/mail/var/dovecot.index.log", 1_900_000),
        ("services/mail/var/stats.tmp", 180_000),
        ("services/mail/var/spool/cur/message-104221.log", 1_450_000),
        ("services/mail/var/spool/cur/message-104222.log", 1_320_000),
        ("services/mail/var/spool/cur/message-104223.log", 1_010_000),
        ("services/mail/var/spool/cur/queue.tmp", 640_000),
        ("services/mail/var/spool/cur/spool.pid", 1_024),
        ("services/mail/var/spool/tmp/maild.tmp", 240_000),
        ("services/mail/var/spool/new/core.dovecot", 720_000),
    ]:
        fx.retained(rel, size)
    fx.protect_dirs(roots)

    # ---- junk --------------------------------------------------------------
    jk = [
        ("teams/alpha/workspace-heron/__pycache__/main.cpython-312.pyc", 44_000, J1),
        ("teams/alpha/workspace-heron/node_modules/prism/dist/index.js", 188_000, J2),
        ("teams/alpha/workspace-heron/node_modules/prism/package.json", 1_910, J2),
        ("teams/alpha/workspace-heron/build/obj/main.o", 96_000, J3),
        ("teams/alpha/workspace-heron/build/libs/bundle.bin", 350_000, J3),
        ("teams/alpha/workspace-heron/scratch/9f1c2d3e.bin", 640_000, J1),
        ("teams/alpha/workspace-heron/scratch/77aa44bb.bin", 420_000, J2),
        ("teams/alpha/workspace-heron/scratch/note.tmp", 8_000, J3),
        ("teams/alpha/workspace-heron/session.log", 260_000, J2),
        ("teams/alpha/workspace-heron/core.90231", 1_100_000, J1),
        ("teams/alpha/workspace-heron/hotfix.pid", 66, J3),
        ("teams/beta/workspace-vent-2/node_modules/inkwell/index.js", 210_000, J3),
        ("teams/beta/workspace-vent-2/node_modules/inkwell/lock.json", 4_100, J1),
        ("teams/beta/workspace-vent-2/build/artifacts/vent.bin", 620_000, J1),
        ("teams/beta/workspace-vent-2/debug.log", 3_100_000, J1),
        ("teams/beta/workspace-vent-2/core.4412", 980_000, J2),
        ("teams/beta/workspace-vent-2/scratch/a71f.bin", 300_000, J3),
        ("teams/beta/workspace-vent-2/scratch/e9c0.bin", 150_000, J1),
        ("services/notify/notifications.log", 1_800_000, J2),
        ("services/notify/cache/locks.tmp", 12_000, J3),
    ]
    for rel, size, mt in jk:
        fx.junk(rel, size, mt)


def build_h1(fx):
    fx.write_policy({
        "host": "loghost",
        "budget": 3_145_728,    # 3 MiB
        "criteria": {
            "suffixes": [".log", ".tmp", ".pid"],
            "dir_names": ["tmp", "cache"],
            "prefixes": ["core."],
            "min_size_bytes": 0,
        },
    })
    roots = ["app/web/tmp/retention_hold"]
    fx.write_manifest(roots)
    fx.write_readme(README_H1)

    fx.real("config/routes.yaml", "routes:\n  - /ingest -> app\n")
    fx.real("bin/healthcheck.sh", "#!/bin/sh\nexit 0\n", mode=0o755)
    fx.real_blob("archive/catalog.sqlite", 900_000)

    for rel, size in [
        ("app/web/tmp/retention_hold/chunk-0001.log", 640_000),
        ("app/web/tmp/retention_hold/chunk-0002.log", 380_000),
        ("app/web/tmp/retention_hold/blob.tmp", 400_000),
        ("app/web/tmp/retention_hold/index.log", 120_000),
    ]:
        fx.retained(rel, size)
    fx.protect_dirs(roots)

    fx.junk("ingress/request.log", 2_700_000, J1)
    fx.junk("ingress/response.log", 1_100_000, J2)
    for i in range(1, 25):
        fx.junk("app/web/tmp/chunk-%02d.tmp" % i, 90_000,
                (J1, J2, J3)[i % 3])
    fx.junk("app/web/tmp/session.pid", 1_024, J2)
    fx.junk("app/web/cache/items.json", 500_000, J3)
    fx.junk("var/crash/core.9901", 1_900_000, J1)
    fx.junk("var/crash/core.9902", 300_000, J2)


def build_h2(fx):
    fx.write_policy({
        "host": "cifarm",
        "budget": 6_291_456,    # 6 MiB
        "criteria": {
            "suffixes": [".log", ".tmp", ".bak"],
            "dir_names": ["node_modules", "build", "dist"],
            "prefixes": ["core."],
            "min_size_bytes": 1024,
        },
    })
    roots = ["runner/vault", "runner/recordings"]
    fx.write_manifest(roots)
    fx.write_readme(README_H2)

    fx.real("runner/workspaces/w1/src/main.py",
            "def main():\n    return 'w1'\n")
    fx.real("runner/workspaces/w1/README.md", "# job w1\n")
    fx.real("runner/workspaces/w2/notes.txt", "notes for w2\n")
    fx.real("runner/workspaces/w1/tiny.log", "oops\n")          # <1KiB: NOT junk
    fx.real("runner/workspaces/w1/node_modules/pkgc/README.txt",
            "tiny package note\n")                               # <1KiB: NOT junk

    for rel, size in [
        ("runner/vault/core.vault-77", 990_000),
        ("runner/vault/crash-1301.tmp", 1_100_000),
        ("runner/vault/spool.log", 260_000),
        ("runner/recordings/segment-0412.tmp", 1_900_000),
        ("runner/recordings/index.log", 310_000),
    ]:
        fx.retained(rel, size)
    fx.protect_dirs(roots)

    fx.junk("runner/workspaces/w1/node_modules/pkga/x.js", 200_000, J1)
    fx.junk("runner/workspaces/w1/node_modules/pkgb/y.js", 150_000, J2)
    fx.junk("runner/workspaces/w1/node_modules/pkgb/z.log", 90_000, J3)
    fx.junk("runner/workspaces/w1/build/artifacts/w1.bin", 4_200_000, J1)
    fx.junk("runner/workspaces/w1/stale artifact (1).log", 1_400_000, J2)
    fx.junk("runner/workspaces/w1/core.9101", 2_200_000, J3)
    fx.junk("runner/workspaces/w2/dist/bundle.min.js", 460_000, J1)
    fx.junk("runner/workspaces/w2/dev.log", 45_000, J2)
    fx.junk("runner/workspaces/w2/old backup.bak", 330_000, J3)


def build_h3(fx):
    fx.write_policy({
        "host": "relay-farm",
        "budget": 5_242_880,    # 5 MiB
        "criteria": {
            "suffixes": [".log", ".tmp", ".pid", ".sqlite-journal"],
            "dir_names": ["junk", ".cache"],
            "prefixes": ["core.", ".nfs", "~$"],
            "min_size_bytes": 0,
        },
    })
    roots = ["var/hold"]
    fx.write_manifest(roots)
    fx.write_readme(README_H3)

    fx.real("config/relay.yaml", "upstream: relay-01\nport: 9000\n")
    fx.real_blob("var/lib/relay.sqlite", 2_050_000)

    for rel, size in [
        ("var/hold/core.signal-7", 780_000),
        ("var/hold/.nfs-0412.tmp", 520_000),
        ("var/hold/~$report.tmp", 240_000),
        ("var/hold/queue.log", 300_000),
    ]:
        fx.retained(rel, size)
    fx.protect_dirs(roots)

    fx.junk("services/gateway/run.log", 3_000_000, J1)
    fx.junk("services/gateway/.cache/idx.ldb", 1_000_000, J2)
    fx.junk("services/gateway/junk/old-segment-0.dat", 640_000, J3)
    fx.junk("services/gateway/junk/old-segment-1.dat", 610_000, J1)
    fx.junk("var/crash/core.7712", 1_050_000, J2)
    fx.junk("run.pid", 80, J3)


BUILDERS = {
    "meridian": build_meridian,
    "h1": build_h1,
    "h2": build_h2,
    "h3": build_h3,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True, choices=sorted(BUILDERS))
    ap.add_argument("--root", required=True)
    ap.add_argument("--catalog", default=None)
    args = ap.parse_args()

    fx = Fixture(args.profile, args.root)
    BUILDERS[args.profile](fx)
    orig, nonjunk, junk_total = fx.assert_feasible()
    if args.catalog:
        fx.write_catalog(args.catalog)
    print("profile=%s root=%s original=%d non_junk=%d junk=%d budget=%d" %
          (args.profile, args.root, orig, nonjunk, junk_total,
           fx.policy["budget_bytes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())