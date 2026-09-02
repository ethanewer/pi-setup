#!/bin/bash
# Edge: analytics venv already exists and is reasonable, but the server venv
# and the jupyter config are missing.
rm -rf /app/venvs
python3 -m venv --system-site-packages /app/venvs/analytics
rm -f /app/jupyter_config.py /app/requirements.lock
