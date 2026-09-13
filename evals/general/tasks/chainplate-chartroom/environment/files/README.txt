Environment notes for chainplate-chartroom.

- /app/src is the pinned clone of python-poetry/poetry (parent commit
  e54180064368c2f9d9ad5ff4771d8b33538cc372), installed editable into
  /opt/poetry-venv. No network at trial time; no git remotes.
- Run the suite from /app/src with:
    /opt/poetry-venv/bin/pytest tests/config/ -p no:randomly -o addopts="" -q
- /opt/golden, /tests and /solution are harness-owned; do not touch them.