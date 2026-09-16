FROM bench-base:python-3.12

# ---------------------------------------------------------------------------
# corbel-weir: release/packaging task against the real upstream pallets/click.
# The frozen upstream tag is 8.5.0. Tags can be force-moved upstream, so the
# clone is rejected unless HEAD resolves to the exact commit that was measured
# when this task was authored.
# ---------------------------------------------------------------------------
ARG UPSTREAM_SHA=8b19813f2bfca99f1018a587a8cf54fc959f2e5d
RUN git clone --depth 1 --branch 8.5.0 https://github.com/pallets/click.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Build frontend, the project's declared backend, and pytest for the project's
# own test suite. All pinned; the trial has no network, so nothing may be
# fetched at trial time.
RUN pip install --no-cache-dir build==1.6.0 flit_core==3.12.0 pytest==8.4.2

# ---------------------------------------------------------------------------
# Seed the release-metadata defect. Authored here, in the task's own
# Dockerfile, so the audit can see exactly what we changed: the [project]
# version line no longer matches the upstream 8.5.0 tag. The build itself
# still succeeds; every resulting artifact is simply mislabeled. The agent
# must find and repair it.
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
p = Path("/app/src/pyproject.toml")
t = p.read_text()
bad, good = 'version = "8.5.0"', 'version = "9.9.0"'
assert t.count(bad) == 1, "seed anchor not found exactly once; upstream may have changed"
p.write_text(t.replace(bad, good, 1))
print("seeded release-metadata defect in /app/src/pyproject.toml")
PY

WORKDIR /app

COPY files/ /app/