"""Harbor agent matching the user's local `p` pi setup.

The local `p` wrapper (~/.local/bin/p) runs pi with:
  --no-extensions --no-skills
plus a handful of host-specific extensions (voice STT, context-handoff,
btw, mlx) that only make sense on the macOS host, not inside an eval
container.  The eval-relevant essence of `p` is therefore pi's lean
profile with no extensions and no skills.

This agent subclasses harbor's built-in Pi agent and injects the
`--no-extensions --no-skills` flags into the run command so the
in-container agent behaves like the `p` lean profile.

Run with:
  PYTHONPATH=<benchmark>/agents harbor run -a p_agent:PAgent \
      -m openrouter/deepseek/deepseek-v4-flash-0731 ...
"""

import shlex
from pathlib import Path
from typing import override

from harbor.agents.installed.pi import Pi, with_prompt_template
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext

# The bench-base images bake this pinned Pi plus the repo's reasoning-details
# fix. harbor's stock install resolves @latest -> pi-ai 0.84.3, whose
# fragmented reasoning_details replay contaminates multi-turn rollouts (see
# docs/incidents/PI-AI-0.84.3-REASONING-DETAILS.md); the upstream fix is not
# in any published release, so never let npm touch the baked install.
#
# The fix must target pi's npm entrypoint: bin -> dist/bundle/cli.js loads
# pi-ai from dist/bundle/chunks/openai-completions-*.js, NOT node_modules.
_PI_PIN = "0.84.3"
_PI_AI_PATCH_MARKER = "normalizeOpenAIReasoningDetails"
_PI_AI_BUG_PATTERN = "preservedDetails.push(detail)"
_PATCH_PI_BUNDLE = Path(__file__).resolve().parents[3] / "bin" / "patch-pi-bundle"


def _pi_bake_verify_command() -> str:
    return (
        "set -e; . ~/.nvm/nvm.sh; "
        'v="$(pi --version | tail -n 1)"; '
        f'[ "$v" = "{_PI_PIN}" ]; '
        'PI_ROOT="$(npm root -g)/@earendil-works/pi-coding-agent"; '
        f'grep -q {_PI_AI_PATCH_MARKER} '
        f'"$PI_ROOT"/dist/bundle/chunks/openai-completions-*.js && '
        f'! grep -q "{_PI_AI_BUG_PATTERN}" '
        '"$PI_ROOT"/dist/bundle/chunks/openai-completions-*.js'
    )


class PAgent(Pi):
    """Pi agent running in the lean `p` profile (no extensions/skills)."""

    @staticmethod
    @override
    def name() -> str:
        return "p-pi"

    @override
    async def install(self, environment: BaseEnvironment) -> None:
        # Fast path: the task image descends from a bench-base image with the
        # pinned, patched Pi baked in. Verify it and skip npm entirely.
        result = await self.exec_as_agent(
            environment, command=_pi_bake_verify_command()
        )
        if result.return_code == 0:
            return

        # Fallback for non-bench-base images (item-052-main, skill-pdflatex
        # use texlive/texlive): pinned install, then patch the bundle chunk
        # in-container with the same version-guarded patcher.
        from harbor.agents.installed.node_install import nvm_node_install_snippet

        await self.ensure_system_dependencies(
            environment, ("curl", "python3")
        )
        await self.exec_as_agent(
            environment,
            command=(
                "set -euo pipefail; "
                f"{nvm_node_install_snippet()} && "
                f"npm install -g --ignore-scripts "
                f"@earendil-works/pi-coding-agent@{_PI_PIN} && "
                "pi --version"
            ),
        )
        await environment.upload_file(_PATCH_PI_BUNDLE, "/tmp/patch-pi-bundle")
        result = await self.exec_as_agent(
            environment,
            command=(
                "set -eo pipefail; . ~/.nvm/nvm.sh; "
                "python3 /tmp/patch-pi-bundle "
                '"$(npm root -g)/@earendil-works/pi-coding-agent"'
            ),
        )
        if result.return_code != 0:
            raise RuntimeError(
                "Failed to patch the pi bundle in-container; refusing to run "
                "rollouts on unpatched pi-ai 0.84.3. "
                f"stderr: {result.stderr[-2000:] if result.stderr else ''}"
            )

    @override
    @with_prompt_template
    async def run(
        self,
        instruction: str,
        environment: BaseEnvironment,
        context: AgentContext,
    ) -> None:
        # Identical to Pi.run(), but the pi invocation carries the lean
        # `p` profile flags.  Kept in sync with harbor 0.22.0 pi.py.
        escaped_instruction = shlex.quote(instruction)

        if not self.model_name or "/" not in self.model_name:
            raise ValueError("Model name must be in the format provider/model_name")

        provider, model_id = self.model_name.split("/", 1)
        access = self.model_connection
        provider = access.provider or provider
        env = dict(access.env)
        if provider == "anthropic" and (
            oauth_token := self._get_env("ANTHROPIC_OAUTH_TOKEN")
        ):
            env["ANTHROPIC_OAUTH_TOKEN"] = oauth_token

        models_json = self._build_custom_models_json(access, model_id)
        pi_env_prefix = ""
        if models_json is not None:
            from harbor.agents.installed.pi import _PI_CONFIG_DIR_ENV, _REMOTE_PI_CONFIG_DIR, _CUSTOM_PROVIDER

            await self._write_custom_models_json(environment, models_json)
            pi_env_prefix = (
                f"{_PI_CONFIG_DIR_ENV}={shlex.quote(_REMOTE_PI_CONFIG_DIR.as_posix())} "
            )
            provider = _CUSTOM_PROVIDER

        model_args = f"--provider {provider} --model {model_id} "

        cli_flags = self.build_cli_flags()
        if cli_flags:
            cli_flags += " "
        resume_flag = "--continue " if self._resume else ""

        # The `p` lean profile.
        profile_flags = "--no-extensions --no-skills "

        skills_command = self._build_register_skills_command()
        if skills_command:
            await self.exec_as_agent(environment, command=skills_command)

        await self.exec_as_agent(
            environment,
            command=(
                f". ~/.nvm/nvm.sh; "
                f"{pi_env_prefix}pi --print --mode json "
                f"{profile_flags}"
                f"--session-dir /logs/agent/pi/sessions "
                f"{resume_flag}"
                f"{model_args}"
                f"{cli_flags}"
                f"{escaped_instruction} "
                f'2>&1 </dev/null | grep -v \'"type":"message_update"\' | stdbuf -oL tee /logs/agent/{self._OUTPUT_FILENAME}'
            ),
            env=env,
        )
