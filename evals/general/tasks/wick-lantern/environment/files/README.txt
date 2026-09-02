Wick Lantern lightroom
======================

Write the Jupyter Server config deliverable at /app/jupyter_config.py
(see the task instructions for the exact contract).

Local smoke test (example, port 7931):

    mkdir -p /tmp/lr
    LANTERN_PORT=7931 jupyter server \
        --config=/app/jupyter_config.py --no-browser --allow-root \
        --ServerApp.root_dir=/tmp/lr

Then check http://127.0.0.1:7931/api/status answers HTTP 200 with no
credentials, and stop the server.

This file is a convenience note only; nothing here is graded.
