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
from typing import override

from harbor.agents.installed.pi import Pi, with_prompt_template
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext


class PAgent(Pi):
    """Pi agent running in the lean `p` profile (no extensions/skills)."""

    @staticmethod
    @override
    def name() -> str:
        return "p-pi"

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
