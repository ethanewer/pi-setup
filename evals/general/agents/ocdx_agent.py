"""Harbor agent matching the user's `ocdx` setup (Codex CLI on OpenRouter's
pinned open-weight models, responses wire API).

Fidelity approach: upload the LIVE setup wrapper (lib/wrappers/ocdx.sh) and
the installer-managed Codex config (~/.pi/agent-ocdx/codex/config.toml +
models.json) and run codex THROUGH the wrapper. The wrapper owns the
closed-model refusal, the effort default, the session-flag pins
(model_provider/model_reasoning_effort/service_tier), and the
approvals/sandbox bypass; the managed config owns the endpoint and wire API.
The container's codex CLI is pinned to the HOST codex version at install.

Output convention matches harbor's codex agent (exec --json teed to
/logs/agent/codex.txt), so downstream gates/collectors parse it unchanged.

Run with:
  PYTHONPATH=<benchmark>/agents harbor run -a ocdx_agent:OcdxAgent \
      -m z-ai/glm-5.3-flash ...
(bare OpenRouter slug or openrouter/-prefixed; the prefix is stripped.)
"""
from __future__ import annotations

import shlex
from typing import override

import setup_sync
from harbor.agents.installed.codex import Codex
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext
from harbor.models.trial.paths import EnvironmentPaths


class OcdxAgent(Codex):
    """Codex launched through the setup's ocdx wrapper with the managed config."""

    @staticmethod
    @override
    def name() -> str:
        return "ocdx"

    @override
    async def install(self, environment: BaseEnvironment) -> None:
        host_version = setup_sync.codex_version()
        if not host_version:
            # setup_sync contract: fail loud rather than let harbor's @latest
            # silently drift from the setup's engine.
            raise RuntimeError(
                "cannot derive the host codex version (`codex --version`); "
                "refusing to install an unpinned engine that may drift from the setup"
            )
        self._version = host_version
        await super().install(environment)
        await environment.upload_file(
            str(setup_sync.wrapper_script("ocdx")), "/tmp/hb-ocdx.sh"
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

        remote_home = self._REMOTE_CODEX_HOME.as_posix()
        managed = setup_sync.ocdx_managed_config()

        await self.exec_as_agent(
            environment,
            command=f'mkdir -p {shlex.quote(remote_home)}',
        )
        for name, host_path in managed.items():
            if name == "config.toml":
                # The managed config references the host's model catalog by
                # absolute path; rewrite it to the uploaded copy ON THE HOST
                # (no in-container sed quoting games). Host-specific project
                # trust entries simply never match inside the container.
                import tempfile
                from pathlib import Path

                text = host_path.read_text().replace(
                    f"{setup_sync.HOST_OCDX_HOME}/models.json",
                    f"{remote_home}/models.json",
                )
                with tempfile.NamedTemporaryFile(
                    "w", suffix="-config.toml", delete=False
                ) as f:
                    f.write(text)
                    tmp_cfg = f.name
                try:
                    await environment.upload_file(tmp_cfg, f"{remote_home}/config.toml")
                finally:
                    Path(tmp_cfg).unlink(missing_ok=True)
            else:
                await environment.upload_file(str(host_path), f"{remote_home}/{name}")

        escaped = shlex.quote(instruction)
        out = (EnvironmentPaths.agent_dir / self._OUTPUT_FILENAME).as_posix()
        await self.exec_as_agent(
            environment,
            command=(
                'export PATH="$HOME/.local/bin:$PATH"; '
                ". ~/.nvm/nvm.sh 2>/dev/null || true; "
                f"bash /tmp/hb-ocdx.sh --model {shlex.quote(slug)} "
                f"exec --skip-git-repo-check --json {escaped} "
                f"2>&1 </dev/null | tee {out}"
            ),
            env={"OPENROUTER_API_KEY": key, "CODEX_HOME": remote_home},
        )
