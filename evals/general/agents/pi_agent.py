"""Harbor agent matching the user's FULL `pi` setup.

The container gets:
  * the pi version pinned by the host setup, with the setup's
    reasoning-details patch (pi_setup_base.SetupPiInstallMixin), and
  * the setup's container-safe extension forks, uploaded as the HOST
    installer compiled them (~/.pi/agent/local/<fork>, index.js included)
    and registered through ~/.pi/agent/settings.json packages.

Host-only forks are excluded on purpose (voice-stt needs macOS audio, mlx
needs Apple MLX); see setup_sync.CONTAINER_SAFE_FORKS. The run itself is
harbor's stock Pi.run() — plain `pi --print --mode json` with no profile
flags — so the full-profile surface is exactly what the installed pi plus
the shipped forks provide. Updating the host setup updates this agent with
no eval changes.

Run with:
  PYTHONPATH=<benchmark>/agents harbor run -a pi_agent:PiSetupAgent \
      -m openrouter/z-ai/glm-5.3-flash ...
"""
from __future__ import annotations

import io
import json
import shlex
import tarfile
import tempfile
from pathlib import Path
from typing import override

import setup_sync
from harbor.agents.installed.pi import Pi
from harbor.environments.base import BaseEnvironment
from pi_setup_base import SetupPiInstallMixin


def _forks_tarball() -> bytes:
    """tar.gz of every installed container-safe fork (minus node_modules/.git)."""
    forks = setup_sync.installed_forks()
    if not forks:
        raise RuntimeError(
            "no container-safe forks installed under ~/.pi/agent/local — run the "
            "pi-setup installer first (it compiles the forks the pi profile loads)"
        )
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for name, src in forks.items():
            def filter_(ti: tarfile.TarInfo, _src=src) -> tarfile.TarInfo | None:
                parts = ti.name.split("/")
                if "node_modules" in parts or ".git" in parts:
                    return None
                return ti
            tf.add(str(src), arcname=name, filter=filter_, recursive=True)
    return buf.getvalue()


class PiSetupAgent(SetupPiInstallMixin, Pi):
    """Pi with the host setup's version, patch, and extension forks."""

    @staticmethod
    @override
    def name() -> str:
        return "pi-setup"

    @override
    async def install(self, environment: BaseEnvironment) -> None:
        await super().install(environment)

        forks = setup_sync.installed_forks()
        tarball = _forks_tarball()
        tmp = "/tmp/pi-setup-forks.tgz"
        with tempfile.NamedTemporaryFile(suffix=".tgz", delete=False) as f:
            f.write(tarball)
            host_tmp = f.name
        try:
            await environment.upload_file(host_tmp, tmp)
        finally:
            Path(host_tmp).unlink(missing_ok=True)

        packages = [f"local/{name}" for name in sorted(forks)]
        settings = json.dumps({"packages": packages}, indent=2)
        await self.exec_as_agent(
            environment,
            command=(
                "set -euo pipefail; "
                'mkdir -p "$HOME/.pi/agent/local"; '
                f"tar -xzf {tmp} -C \"$HOME/.pi/agent/local\"; "
                f"printf '%s' {shlex.quote(settings)} > \"$HOME/.pi/agent/settings.json\"; "
                'ls "$HOME/.pi/agent/local"'
            ),
        )

    # run(): inherited from harbor's Pi — the full profile is the default
    # surface once the forks and settings above are in place.
