#!/usr/bin/env python3
"""Repair for yard-sloop: keep the `_git` segment in Azure DevOps project URLs.

Semgrep's git-URL parser strips the `/_git` path segment from the owner of an
Azure DevOps remote but discards the fact that it stripped it, and the project
URL is then rebuilt as protocol://resource/owner/name without `_git`, so every
finding link for such a repository points at a page that does not exist.

This applies the same change the upstream project made to fix the bug:
 - Parser records `azure_git_dir` ('/_git') whenever the owner ends with
   '/_git', and Parser.Parse() exposes it as an additional field;
 - the project-URL builder re-appends `azure_git_dir` when rebuilding the URL.

It also reconciles the project's own tracked regression test (which still
encoded the pre-fix expectation) with the corrected behaviour, exactly as the
upstream fix commit did, and writes the /app/reproduce.py deliverable.
"""
import os
import shutil
import sys

ROOT = "/app/src"
PARSER = os.path.join(ROOT, "cli", "src", "semgrep", "external", "git_url_parser.py")
META = os.path.join(ROOT, "cli", "src", "semgrep", "meta.py")
TREE_TEST = os.path.join(ROOT, "cli", "tests", "default", "e2e-pro", "test_meta.py")
GOLDEN = "/opt/golden/test_meta.py"
REPRO = "/app/reproduce.py"

# ---- 1. source repair: git_url_parser.py -----------------------------------
p = open(PARSER).read()
q = p

namedtuple_patch = "'name',\n    'owner',\n])"
assert namedtuple_patch in q, "parser: namedtuple anchor missing"
q = q.replace(namedtuple_patch, "'name',\n    'owner',\n    'azure_git_dir',\n])")

defaults_patch = "'name': None,\n            'owner': None,\n        }"
assert defaults_patch in q, "parser: defaults anchor missing"
q = q.replace(defaults_patch, "'name': None,\n            'owner': None,\n            'azure_git_dir': '',\n        }")

azure_patch = (
    "        if d['owner'] is not None and cast(str, d['owner']).endswith('/_git'):  # Azure DevOps Git URLs\n"
    "            d['owner'] = d['owner'][:-len('/_git')]"
)
assert azure_patch in q, "parser: azure anchor missing"
q = q.replace(
    azure_patch,
    "        if d['owner'] is not None and cast(str, d['owner']).endswith('/_git'):  # Azure DevOps Git URLs\n"
    "            d['azure_git_dir'] = '/_git'\n"
    "            d['owner'] = d['owner'][:-len('/_git')]",
)
open(PARSER, "w").write(q)

# ---- 2. source repair: meta.py ---------------------------------------------
m = open(META).read()
assert "result.azure_git_dir" not in m, "meta: fix already applied?"
url_build = 'return f"{protocol}://{result.resource}/{result.owner}/{result.name}"'
assert url_build in m, "meta: URL build anchor missing"
m = m.replace(
    url_build,
    'return f"{protocol}://{result.resource}/{result.owner}{result.azure_git_dir}/{result.name}"',
)
open(META, "w").write(m)

# ---- 3. reconcile the project's own tracked regression test ----------------
# The fixed-era test (authoritative copy in the image) asserts the corrected
# expectations; the parent-era tracked test encoded the buggy ones. Replace
# it with the corrected expectations, as the upstream fix commit did.
assert os.path.isfile(TREE_TEST) and os.path.isfile(GOLDEN)
shutil.copyfile(GOLDEN, TREE_TEST)

# ---- 4. the reproduction deliverable ----------------------------------------
repro = """#!/usr/bin/env python3
\"\"\"Reproduction for: Azure DevOps project URLs lose the `_git` segment.

Computes what the installed Semgrep produces for an Azure DevOps remote and
reports whether the result is correct. Prints one line `url=<result>` and
exits 0 iff the result keeps the `_git` segment.
\"\"\"
import sys

from semgrep.meta import get_url_from_sstp_url

REMOTE = "https://test@dev.azure.com/test/TestName/_git/Core.Thing"
EXPECTED = "https://dev.azure.com/test/TestName/_git/Core.Thing"


def main() -> int:
    got = get_url_from_sstp_url(REMOTE)
    print(f"url={got}")
    return 0 if got == EXPECTED else 1


if __name__ == "__main__":
    sys.exit(main())
"""
with open(REPRO, "w") as f:
    f.write(repro)
os.chmod(REPRO, 0o755)

print("repair applied: parser + meta patched, tracked regression test reconciled, /app/reproduce.py written")