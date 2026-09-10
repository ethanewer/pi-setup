#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Authoring helper: emit solution/migrate.py from the corpus modules.

Run on the HOST (never shipped): concatenates the renderer and every
corpus module into one self-contained migration script that re-renders
the repository in STRICT mode at oracle time, then re-runs the strict
self-check. Keeping the oracle generated from the same corpus files as
the fixture guarantees the reference migration matches the shipped
repository exactly.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TASK = os.path.abspath(os.path.join(HERE, "..", "..", ".."))  # tasks/<name>
OUT = os.path.join(TASK, "solution", "migrate.py")

MODULES = [
    "renderer",
    "corpus_util",
    "corpus_model",
    "corpus_data",
    "corpus_data2",
    "corpus_reports",
    "corpus_svc",
    "corpus_legacy",
    "corpus_add1",
    "corpus_add2",
    "corpus_add3",
    "corpus_addf",
    "corpus_addg",
    "corpus_tests_a",
    "corpus_tests_b",
    "corpus_matrix",
    "corpus_matrix2",
    "corpus_tests",
]

TAIL = '''
import os
import sys
import json

PKG = {
    "name": "cistern",
    "version": "1.4.2",
    "description": "water-distribution modelling, ledgers and billing (TypeScript)",
    "type": "module",
    "engines": {"node": ">=18"},
    "scripts": {"typecheck": "tsc --noEmit -p tsconfig.json", "test": "vitest run"},
    "devDependencies": {"typescript": "5.9.3", "vitest": "3.2.4", "vite": "7.2.2"},
}

VITEST_CFG = """import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
  },
});
"""

README = """# cistern

A TypeScript library for water-distribution network modelling and billing:
telemetry ingestion, meter ledgers, tiered tariffs, flow balancing, nightly
leak detection and text reports.

## Commands

    npm run typecheck   # tsc --noEmit -p tsconfig.json
    npm test            # vitest run
"""

GITIGNORE = """node_modules/
coverage/
*.log
"""


def strict_config():
    """The fully hardened strict tsconfig the migration commits to."""
    import json as _json

    cfg = {
        "compilerOptions": {
            "target": "ES2022",
            "module": "ESNext",
            "moduleResolution": "bundler",
            "lib": ["ES2022"],
            "strict": True,
            "strictNullChecks": True,
            "noImplicitAny": True,
            "noUncheckedIndexedAccess": True,
            "exactOptionalPropertyTypes": True,
            "noImplicitOverride": True,
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
        "include": ["src", "tests"],
    }
    return _json.dumps(cfg, indent=2)


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "/app/cistern"
    files = (
        CUT + CMODEL + CDATA + CDATA2 + CREPORTS + CSVC + CLEGACY
        + CADD + CADD2 + CADD3 + CADDF + CADDG + CTESTS
    )
    for rel, text in files:
        path = os.path.join(out, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(render(text, True))

    import json as _json

    with open(os.path.join(out, "package.json"), "w", encoding="utf-8") as fh:
        fh.write(_json.dumps(PKG, indent=2) + "\\n")
    with open(os.path.join(out, "tsconfig.json"), "w", encoding="utf-8") as fh:
        fh.write(strict_config() + "\\n")
    with open(os.path.join(out, "vitest.config.ts"), "w", encoding="utf-8") as fh:
        fh.write(VITEST_CFG)
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(README)
    with open(os.path.join(out, ".gitignore"), "w", encoding="utf-8") as fh:
        fh.write(GITIGNORE)
    print("cistern migrated to strict mode at %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
'''


def main():
    parts = []
    for mod in MODULES:
        path = os.path.join(HERE, mod + ".py")
        if not os.path.exists(path):
            raise SystemExit("missing corpus module %s" % path)
        parts.append(open(path, encoding="utf-8").read())
    def strip_sibling_imports(code: str) -> str:
        lines = []
        for line in code.splitlines():
            stripped = line.strip()
            if stripped.startswith(("from corpus_", "import corpus_")):
                continue
            lines.append(line)
        return "\n".join(lines)

    body = "\n\n# ================= module: %s =================\n\n".join(
        ["# cistern-loom oracle migration script (generated; do not hand-edit)."]
        + [strip_sibling_imports(p) for p in parts]
    )
    # corpus files are entires of name collisions on the shared name, so
    # keep the module code exactly as authored (they are plain lists of
    # tuples, safe to concatenate).
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(body)
        fh.write(TAIL)
    os.chmod(OUT, 0o644)
    print("wrote %s (%d bytes)" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()