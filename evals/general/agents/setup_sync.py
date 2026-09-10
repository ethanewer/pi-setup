"""Single source of truth: the HOST pi-setup installation.

Every general-eval agent derives its in-container pi/claude/codex versions,
the reasoning-details patch, and the setup wrappers from the LIVE host setup
(lib/versions.json, patches/, lib/wrappers/, ~/.pi/agent/local), so updating
the setup (install.sh / the update-pi-setup skill / bin/pi-setup-doctor)
never requires editing an eval agent.

Nothing here may hardcode a version. If a value cannot be derived from the
host setup, fail loudly instead of falling back to a stale constant.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # pi-setup repo root (agents/ -> general/ -> evals/ -> repo)
VERSIONS_FILE = REPO / "lib" / "versions.json"
PATCHES_DIR = REPO / "patches"
WRAPPERS_DIR = REPO / "lib" / "wrappers"
HOST_AGENT_LOCAL = Path.home() / ".pi" / "agent" / "local"
HOST_OCDX_HOME = Path.home() / ".pi" / "agent-ocdx" / "codex"

# Forks that make sense in a headless Linux container. Host-only forks are
# excluded on purpose: voice-stt needs macOS audio, mlx needs Apple MLX.
CONTAINER_SAFE_FORKS = [
    "pi-process-monitor-safe",
    "pi-dynamic-workflows-safe",
    "pi-btw-side",
    "pi-context-handoff",
]
HOST_ONLY_FORKS = ["pi-voice-stt-safe", "mlx"]

# Patch markers used to verify a container install carries the fix. Derived
# from the patch file itself where possible so a future patch revision does
# not silently invalidate them.
PATCH_MARKER = "normalizeOpenAIReasoningDetails"
PATCH_BUG_PATTERN = "preservedDetails.push(detail)"


def versions() -> dict:
    """The setup's pinned CLI versions (lib/versions.json)."""
    return json.loads(VERSIONS_FILE.read_text())


def pi_pin() -> str:
    return str(versions()["pi"])


def pi_ai_pin() -> str:
    return str(versions()["piAi"])


def reasoning_patch_file() -> Path:
    """The reasoning-details patch matching the pinned pi-ai. Exact match only:
    guessing a neighboring version's patch would apply wrong code to the
    in-container engine while still printing PI_BUNDLE_PATCHED."""
    exact = PATCHES_DIR / f"pi-ai@{pi_ai_pin()}-reasoning-details.patch"
    if not exact.exists():
        raise FileNotFoundError(
            f"missing {exact}: the setup pins pi-ai {pi_ai_pin()} but the repo has no "
            "matching reasoning-details patch; refusing to substitute another version's patch"
        )
    return exact


def patch_pi_bundle_script() -> Path:
    """bin/patch-pi-bundle from the repo (live), not a copy that can drift."""
    p = REPO / "bin" / "patch-pi-bundle"
    if not p.exists():
        raise FileNotFoundError(f"missing {p}")
    return p


def _cli_version(cmd: list[str], pattern: str) -> str | None:
    exe = shutil.which(cmd[0])
    if not exe:
        return None
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return None
    m = re.search(pattern, out)
    return m.group(1) if m else None


def claude_version() -> str | None:
    """Host claude CLI version (occ's engine), e.g. '2.1.241'."""
    return _cli_version(["claude", "--version"], r"(\d+\.\d+\.\d+)")


def codex_version() -> str | None:
    """Host codex CLI version (ocdx's engine), e.g. '0.153.4'."""
    return _cli_version(["codex", "--version"], r"(\d+\.\d+\.\d+)")


def wrapper_script(name: str) -> Path:
    """lib/wrappers/<name>.sh — the live setup wrapper (occ, ocdx, ...)."""
    p = WRAPPERS_DIR / f"{name}.sh"
    if not p.exists():
        raise FileNotFoundError(f"missing setup wrapper {p}")
    return p


def installed_forks() -> dict[str, Path]:
    """Container-safe forks as INSTALLED (compiled) by the setup's installer.

    These carry the installer-built extensions/monitor/index.js etc., so the
    container gets exactly the artifacts the host setup runs — no eval-side
    build step and no version drift.
    """
    out: dict[str, Path] = {}
    for name in CONTAINER_SAFE_FORKS:
        p = HOST_AGENT_LOCAL / name
        if (p / "package.json").exists():
            out[name] = p
    return out


def ocdx_managed_config() -> dict[str, Path]:
    """The installer-managed Codex config for the ocdx profile."""
    cfg = HOST_OCDX_HOME / "config.toml"
    if not cfg.exists():
        raise FileNotFoundError(
            f"missing {cfg}; run the pi-setup installer (it writes the ocdx provider config)"
        )
    files = {"config.toml": cfg}
    catalog = HOST_OCDX_HOME / "models.json"
    if catalog.exists():
        files["models.json"] = catalog
    return files


def openrouter_key() -> str | None:
    """Resolve the setup's OpenRouter key without prompting (env first, then
    the setup's own credential chain via `pi auth`)."""
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if key:
        return key
    keyfile = Path.home() / ".openrouter-key"
    if keyfile.exists():
        return keyfile.read_text().strip()
    if shutil.which("pi"):
        try:
            out = subprocess.run(
                ["pi", "auth", "print-api-key", "--provider", "openrouter"],
                capture_output=True, text=True, timeout=60,
            ).stdout.strip()
            if out:
                return out
        except Exception:
            pass
    return None
