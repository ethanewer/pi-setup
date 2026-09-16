#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Assemble the cistern repository into OUT (default /app/cistern).

Renders every corpus file in the requested mode (loose for the shipped
fixture, strict for the migration proof), writes the repository metadata
(tsconfig, package.json, vitest config, README, .gitignore) and prints a
shape summary. Git history is staged commit-by-commit by assemble.sh so
each commit is a real state of the tree.
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from renderer import render  # noqa: E402
from corpus_util import CUT  # noqa: E402
from corpus_model import CMODEL  # noqa: E402
from corpus_data import CDATA  # noqa: E402
from corpus_data2 import CDATA2  # noqa: E402
from corpus_reports import CREPORTS  # noqa: E402
from corpus_svc import CSVC  # noqa: E402
from corpus_legacy import CLEGACY  # noqa: E402
from corpus_tests import CTESTS  # noqa: E402
from corpus_add1 import CADD  # noqa: E402
from corpus_add2 import CADD2  # noqa: E402
from corpus_add3 import CADD3  # noqa: E402
from corpus_addf import CADDF  # noqa: E402
from corpus_addg import CADDG  # noqa: E402

ALL_FILES = CUT + CMODEL + CDATA + CDATA2 + CREPORTS + CSVC + CLEGACY + CADD + CADD2 + CADD3 + CADDF + CADDG + CTESTS

README = """# cistern

A TypeScript library for water-distribution network modelling and billing:
telemetry ingestion, meter ledgers, tiered tariffs, flow balancing, nightly
leak detection and text reports.

Pure TypeScript, zero runtime dependencies, deterministic output. All money
flow goes through `src/util/money.ts` in integer cents, rounding only at
report boundaries.

## Layout

    src/util/      error model, money, canonical keys, maths helpers
    src/model/     config freezing, network graph, zones
    src/data/      records, telemetry, ledgers, tariffs
    src/algo/      flow balance, leak detection
    src/reports/   table rendering, zone summaries
    src/service/   ingest pipeline, reconcile orchestration
    src/legacy/    flat-file importers kept for compatibility
    tests/         vitest suite (the specification)

## Commands

    npm run typecheck   # tsc --noEmit -p tsconfig.json
    npm test            # vitest run

## History

The repository keeps a real git history; the most recent refactor
disabled strict mode while the legacy importers were rewritten, and the
strictness is not yet re-enabled. That is the state the repository ships
in.
"""

PKG = {
    "name": "cistern",
    "version": "1.4.2",
    "description": "water-distribution modelling, ledgers and billing (TypeScript)",
    "type": "module",
    "engines": {"node": ">=18"},
    "scripts": {
        "typecheck": "tsc --noEmit -p tsconfig.json",
        "test": "vitest run",
    },
    "devDependencies": {
        "typescript": "5.9.3",
        "vitest": "3.2.4",
        "vite": "7.2.2",
    },
}

# The shipped tsconfig: strictness is OFF. The task is to turn it on and
# migrate every module so the whole tree compiles strictly (and under the
# hardening flags the verifier applies on top).
TSCONFIG_LOOSE = {
    "compilerOptions": {
        "target": "ES2022",
        "module": "ESNext",
        "moduleResolution": "bundler",
        "lib": ["ES2022"],
        "strict": False,
        "strictNullChecks": False,
        "exactOptionalPropertyTypes": False,
        "noUncheckedIndexedAccess": False,
        "noImplicitAny": False,
        "esModuleInterop": True,
        "forceConsistentCasingInFileNames": True,
        "skipLibCheck": True,
        "noEmit": True,
        "isolatedModules": True,
        "useDefineForClassFields": True,
        "types": [],
        "noUnusedLocals": False,
        "noUnusedParameters": False,
    },
    "include": ["src"],
}

# Flags the verifier turns on over the delivered tsconfig. The whole tree
# (every src and tests file + fresh hidden type-contract files) must
# compile with these on.
HARDENING_FLAGS = [
    "noUncheckedIndexedAccess",
    "exactOptionalPropertyTypes",
    "noImplicitOverride",
]

VITEST_CFG = """import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
  },
});
"""

GITIGNORE = """node_modules/
coverage/
*.log
"""


def dump(obj: object) -> str:
    return json.dumps(obj, indent=2)


STAGE_ORDER = [
    "bootstrap",
    "model",
    "data",
    "algo",
    "reports",
    "service",
    "legacy",
    "api",
    "tests",
    "polish",
]

META_FILES = ["package.json", "tsconfig.json", "vitest.config.ts", "README.md", ".gitignore"]


def stage_rel(stage: str):
    """File paths belonging to a git-history stage."""
    rels = []
    for rel, _text in ALL_FILES:
        if rel.startswith(f"src/util/") or rel == "src/version.ts":
            if stage == "bootstrap":
                rels.append(rel)
        elif rel.startswith("src/model/") or rel.startswith("src/store/"):
            if stage == "model":
                rels.append(rel)
        elif rel.startswith("src/data/"):
            if stage == "data":
                rels.append(rel)
        elif rel.startswith("src/algo/"):
            if stage == "algo":
                rels.append(rel)
        elif rel.startswith("src/reports/"):
            if stage == "reports":
                rels.append(rel)
        elif rel.startswith("src/service/"):
            if stage == "service":
                rels.append(rel)
        elif rel.startswith("src/legacy/"):
            if stage == "legacy":
                rels.append(rel)
        elif rel == "src/index.ts":
            if stage == "api":
                rels.append(rel)
        elif rel.startswith("tests/"):
            if stage == "tests":
                rels.append(rel)
    return rels


def write_meta_file(out: str, base: str, content: str) -> None:
    import os

    path = os.path.join(out, base)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


INDEX_STUB = """// cistern — public surface (bootstrap placeholder).

export const VERSION = "0.0.1";
"""


def build_stage_repo(out: str, mode: str, stage: str) -> None:
    """Render only the files of one history stage; config files only in
    bootstrap; index stub until api stage."""
    if stage == "bootstrap":
        build_meta(out)
        os.makedirs(os.path.join(out, "src"), exist_ok=True)
        with open(os.path.join(out, "src", "index.ts"), "w", encoding="utf-8") as fh:
            fh.write(INDEX_STUB)
        os.makedirs(os.path.join(out, "tests"), exist_ok=True)
    for rel, text in ALL_FILES:
        if rel in stage_rel(stage):
            path = os.path.join(out, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(render(text, mode == "strict"))


def build_meta(out: str) -> None:
    import json

    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "package.json"), "w", encoding="utf-8") as fh:
        fh.write(json.dumps(PKG, indent=2) + "\n")
    with open(os.path.join(out, "tsconfig.json"), "w", encoding="utf-8") as fh:
        fh.write(json.dumps(TSCONFIG_LOOSE, indent=2) + "\n")
    with open(os.path.join(out, "vitest.config.ts"), "w", encoding="utf-8") as fh:
        fh.write(VITEST_CFG)
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(README)
    with open(os.path.join(out, ".gitignore"), "w", encoding="utf-8") as fh:
        fh.write(GITIGNORE)


def build_repo(out: str, mode: str) -> dict:
    for rel, text in ALL_FILES:
        path = os.path.join(out, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(render(text, mode == "strict"))
    with open(os.path.join(out, "package.json"), "w", encoding="utf-8") as fh:
        fh.write(dump(PKG) + "\n")
    with open(os.path.join(out, "tsconfig.json"), "w", encoding="utf-8") as fh:
        fh.write(dump(TSCONFIG_LOOSE) + "\n")
    with open(os.path.join(out, "vitest.config.ts"), "w", encoding="utf-8") as fh:
        fh.write(VITEST_CFG)
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(README)
    with open(os.path.join(out, ".gitignore"), "w", encoding="utf-8") as fh:
        fh.write(GITIGNORE)
    return count_loc(out)


def count_loc(out: str) -> dict:
    total = 0
    files = 0
    for root, dirs, names in os.walk(out):
        dirs[:] = [d for d in dirs if d not in ("node_modules", ".git")]
        for n in names:
            if n.endswith(".ts"):
                with open(os.path.join(root, n), encoding="utf-8") as fh:
                    total += sum(1 for _ in fh)
                files += 1
    return {"loc": total, "files": files}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/app/cistern")
    ap.add_argument("--mode", choices=["loose", "strict"], default="loose")
    ap.add_argument("--stage", choices=STAGE_ORDER, default=None)
    args = ap.parse_args()
    if args.stage is not None:
        build_stage_repo(args.out, args.mode, args.stage)
        print("stage %s rendered into %s" % (args.stage, args.out))
        return 0
    stats = build_repo(args.out, args.mode)
    print("cistern assembled (%s): %d .ts files, %d LOC"
          % (args.mode, stats["files"], stats["loc"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())