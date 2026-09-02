#!/bin/bash
# Edge: the self-contained uv project /app/fathom is missing AND the bash/zsh login
# init files no longer activate conda. Provisioner must recreate the uv project
# (pyproject.toml + uv.lock) and re-write the conda-activating shell init files.
rm -rf /app/fathom
rm -f /root/.bashrc /root/.zshrc
