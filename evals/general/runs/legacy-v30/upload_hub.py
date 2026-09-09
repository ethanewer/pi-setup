#!/usr/bin/env python3
"""Upload hub/v3.0 to eewer/general-agent-bench-results under v3.0/.
Requires HF_TOKEN (write access) in env or /home/ee/.cache/huggingface/token.
"""
import os, sys
from pathlib import Path
from huggingface_hub import HfApi

REPO = "eewer/general-agent-bench-results"
SRC = Path("/home/ee/general-eval-runs/hub/v3.1")
ENV = Path("/home/ee/general-eval-runs/.env")

# load .env (gitignored)
if ENV.exists():
    for line in ENV.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            v = v.strip().strip('"').strip("'")
            os.environ.setdefault(k.strip(), v)

token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
if not token:
    tok = Path.home() / ".cache/huggingface/token"
    if tok.exists():
        token = tok.read_text().strip()
if not token:
    sys.exit("No HF token: set HF_TOKEN (write access to %s)" % REPO)

api = HfApi(token=token)
me = api.whoami()["name"]
print(f"logged in as {me}; uploading {SRC} -> {REPO} (path_in_repo=v3.0)")
url = api.upload_folder(
    folder_path=SRC,
    repo_id=REPO,
    repo_type="dataset",
    path_in_repo="v3.1",
    commit_message="v3.1: uniform 786-task general eval results + normalized traces "
                   "(786 tasks: v3.0 retained + 23 new; removed cinder-hearth/drift-canyon) (pi 'p' / terminus-2 / claude-code x glm-5.3-flash / "
                   "deepseek-v4-flash-0731, 765 tasks, 64 concurrency)",
)
print("commit:", url)
