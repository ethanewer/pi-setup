"""Shared pi install logic for the setup's harbor agents.

Installs the pi version pinned by the HOST setup (lib/versions.json) with the
setup's reasoning-details patch (patches/pi-ai@<ver>-reasoning-details.patch
semantics, applied via the repo's live bin/patch-pi-bundle). Nothing here
pins a version: updating the setup updates the eval.

Fast path: bench-base images bake a pinned+patched pi. The bake check
compares against the CURRENT setup pin, so stale base images automatically
fall through to the in-container install path instead of silently running an
old pi.
"""
from __future__ import annotations

import setup_sync
from harbor.environments.base import BaseEnvironment


def pi_bake_verify_command() -> str:
    """Always exits 0; the PI_BAKE_OK / PI_BAKE_MISSING marker decides the path.

    No `set -e`: on non-bench-base images the nvm source legitimately fails,
    and harbor's exec_as_agent raises on any non-zero exit.
    """
    pin = setup_sync.pi_pin()
    return (
        "( . ~/.nvm/nvm.sh && "
        'v="$(pi --version | tail -n 1)" && '
        f'[ "$v" = "{pin}" ] && '
        'PI_ROOT="$(npm root -g)/@earendil-works/pi-coding-agent" && '
        f'grep -q {setup_sync.PATCH_MARKER} '
        '"$PI_ROOT"/dist/bundle/chunks/openai-completions-*.js && '
        f'! grep -q "{setup_sync.PATCH_BUG_PATTERN}" '
        '"$PI_ROOT"/dist/bundle/chunks/openai-completions-*.js && '
        "echo PI_BAKE_OK ) || echo PI_BAKE_MISSING"
    )


class SetupPiInstallMixin:
    """Install the setup's pinned, patched pi into the container."""

    async def install(self, environment: BaseEnvironment) -> None:  # noqa: D102
        result = await self.exec_as_agent(  # type: ignore[attr-defined]
            environment,
            command=pi_bake_verify_command(),
        )
        if "PI_BAKE_OK" in (result.stdout or ""):
            return

        # Fallback for images without a current bake: install the setup's pin,
        # then patch the bundle chunk in-container with the repo's live
        # version-guarded patcher.
        from harbor.agents.installed.node_install import nvm_node_install_snippet

        pin = setup_sync.pi_pin()
        await self.ensure_system_dependencies(  # type: ignore[attr-defined]
            environment, ("curl", "python3")
        )
        await self.exec_as_agent(  # type: ignore[attr-defined]
            environment,
            command=(
                "set -euo pipefail; "
                f"{nvm_node_install_snippet()} && "
                f"npm install -g --ignore-scripts "
                f"@earendil-works/pi-coding-agent@{pin} && "
                f"npm install -g --ignore-scripts @earendil-works/pi-ai@{setup_sync.pi_ai_pin()} && "
                "pi --version"
            ),
        )
        await environment.upload_file(
            str(setup_sync.patch_pi_bundle_script()), "/tmp/patch-pi-bundle"
        )
        patch_file = setup_sync.reasoning_patch_file()
        await environment.upload_file(str(patch_file), "/tmp/pi-ai-reasoning.patch")
        result = await self.exec_as_agent(  # type: ignore[attr-defined]
            environment,
            command=(
                "set -eo pipefail; . ~/.nvm/nvm.sh; "
                'PI_AI_ROOT="$(npm root -g)/@earendil-works/pi-ai"; '
                'patch --batch --forward -d "$PI_AI_ROOT" -p1 '
                "< /tmp/pi-ai-reasoning.patch || "
                'grep -q normalizeOpenAIReasoningDetails "$PI_AI_ROOT"/dist/api/openai-completions.js; '
                "python3 /tmp/patch-pi-bundle "
                '"$(npm root -g)/@earendil-works/pi-coding-agent" && '
                "echo PI_BUNDLE_PATCHED || echo PI_BUNDLE_PATCH_FAILED"
            ),
        )
        if "PI_BUNDLE_PATCHED" not in (result.stdout or ""):
            raise RuntimeError(
                f"Failed to patch pi for the current setup pin ({pin}); refusing to run "
                "rollouts on an unpatched install. "
                f"stdout: {(result.stdout or '')[-2000:]} "
                f"stderr: {result.stderr[-2000:] if result.stderr else ''}"
            )
