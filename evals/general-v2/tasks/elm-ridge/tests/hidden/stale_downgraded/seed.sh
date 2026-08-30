#!/bin/bash
# Edge: analytics venv exists with OUTDATED package versions (ridgekit 1.0.0,
# sidereal 0.1.0; bundled ridgedf 1.4.0 inherited). Must be upgraded to the pins.
LOCAL=/opt/ridge-index
rm -rf /app/venvs
python3 -m venv --system-site-packages /app/venvs/analytics
/app/venvs/analytics/bin/pip install --quiet --no-index --find-links="$LOCAL" \
    'ridgekit==1.0.0' 'sidereal==0.1.0'
rm -f /app/jupyter_config.py /app/requirements.lock
