#!/bin/bash
# Edge/malformed: analytics venv's interpreter is a plain text file (broken),
# server venv missing. Provisioner must repair by recreating the venv.
rm -rf /app/venvs
mkdir -p /app/venvs/analytics/bin /app/venvs/analytics/lib
printf 'this is not a python interpreter\n' > /app/venvs/analytics/bin/python
chmod +x /app/venvs/analytics/bin/python
rm -f /app/jupyter_config.py /app/requirements.lock
