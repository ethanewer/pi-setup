"""Pi variants with a simplified system prompt and restricted tool sets.

Variant A (PVariantBash):     simplified prompt + bash tool only
Variant B (PVariantBashEdit): simplified prompt + bash + edit (str replace)

Everything else matches PAgent (the `p` lean profile): --no-extensions
--no-skills, JSON print mode, baked patched pi verified at install.
"""

from typing import override

from harbor.agents.installed.pi import with_prompt_template
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext

import shlex

from p_agent import PAgent

SIMPLIFIED_SYSTEM_PROMPT = (
    "You are an expert coding assistant operating inside a coding agent "
    "harness. You help users by reading files, executing commands, editing "
    'code, and writing new files. Current working directory: "$(pwd)"'
)


class _PVariantBase(PAgent):
    """Shared run() with --system-prompt and --tools injected."""

    _TOOLS: str = ""

    @override
    async def run(
        self,
        instruction: str,
        environment: BaseEnvironment,
        context: AgentContext,
    ) -> None:
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
            from harbor.agents.installed.pi import (
                _PI_CONFIG_DIR_ENV,
                _REMOTE_PI_CONFIG_DIR,
                _CUSTOM_PROVIDER,
            )

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

        # Lean `p` profile + variant tool allowlist + simplified system prompt.
        # $(pwd) is expanded inside the container (/app for these tasks).
        profile_flags = (
            f"--no-extensions --no-skills --tools {self._TOOLS} "
            f"--system-prompt {SIMPLIFIED_SYSTEM_PROMPT} "
        )

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


class PVariantBash(_PVariantBase):
    """Simplified system prompt + bash tool only."""

    _TOOLS = "bash"

    @staticmethod
    @override
    def name() -> str:
        return "p-variant-bash"


class PVariantBashEdit(_PVariantBase):
    """Simplified system prompt + bash and edit tools."""

    _TOOLS = "bash,edit"

    @staticmethod
    @override
    def name() -> str:
        return "p-variant-bash-edit"
