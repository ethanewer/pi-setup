"""Harbor agent matching the user's `occ` setup (Claude Code on OpenRouter's
pinned open-weight models).

Fidelity approach: upload the LIVE setup wrapper (lib/wrappers/occ.sh) and run
claude THROUGH it, instead of re-deriving its environment here. The wrapper
owns the endpoint pin (ANTHROPIC_BASE_URL=https://openrouter.ai/api), the
closed-model refusal, the effort default, the tier-slot model mapping, and the
isolated CLAUDE_CONFIG_DIR — so wrapper updates flow into the eval untouched.
The container's claude CLI is pinned to the HOST claude version at install.

Output convention matches harbor's claude-code agent (stream-json teed to
<logs>/claude-code.txt), so downstream gates/collectors parse it unchanged.

Run with:
  PYTHONPATH=<benchmark>/agents harbor run -a occ_agent:OccAgent \
      -m z-ai/glm-5.3-flash ...
(bare OpenRouter slug or openrouter/-prefixed; the prefix is stripped.)
"""
from __future__ import annotations

import shlex
from typing import override

import setup_sync
from harbor.agents.installed.claude_code import ClaudeCode
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext


class OccAgent(ClaudeCode):
    """Claude Code launched through the setup's occ wrapper."""

    @staticmethod
    @override
    def name() -> str:
        return "occ"

    @override
    async def install(self, environment: BaseEnvironment) -> None:
        host_version = setup_sync.claude_version()
        if not host_version:
            # setup_sync contract: fail loud rather than let harbor's @latest
            # silently drift from the setup's engine.
            raise RuntimeError(
                "cannot derive the host claude version (`claude --version`); "
                "refusing to install an unpinned engine that may drift from the setup"
            )
        # Match the container CLI to the host occ engine.
        self._version = host_version
        await super().install(environment)
        await environment.upload_file(
            str(setup_sync.wrapper_script("occ")), "/tmp/hb-occ.sh"
        )

    @override
    async def run(
        self,
        instruction: str,
        environment: BaseEnvironment,
        context: AgentContext,
    ) -> None:
        if not self.model_name:
            raise ValueError("Model name is required")
        slug = self.model_name
        if slug.startswith("openrouter/"):
            slug = slug[len("openrouter/"):]

        key = setup_sync.openrouter_key() or ""
        if not key:
            access = self.model_connection
            key = (access.api_key if access else None) or ""
        if not key:
            raise RuntimeError(
                "no OpenRouter key: set OPENROUTER_API_KEY or store it with "
                "`pi auth` (provider openrouter) on the host running harbor"
            )

        escaped = shlex.quote(instruction)
        out = (self.environment_logs_dir / "claude-code.txt").as_posix()
        await self.exec_as_agent(
            environment,
            command=(
                'export PATH="$HOME/.local/bin:$PATH"; '
                ". ~/.nvm/nvm.sh 2>/dev/null || true; "
                f"bash /tmp/hb-occ.sh --model {shlex.quote(slug)} "
                f"--verbose --output-format=stream-json --print {escaped} "
                f"2>&1 </dev/null | tee {out}"
            ),
            env={"OPENROUTER_API_KEY": key},
        )
