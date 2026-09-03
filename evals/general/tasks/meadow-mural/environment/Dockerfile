FROM bench-base:python-3.12

# meadow-mural — deterministic parametric SVG poster renderer bench.
# Only the visible poster spec is shipped in the image; the renderer script
# and the rendered poster are the agent's deliverables. Everything runs on
# the Python 3.12 stdlib (json, sys, xml) — no extra packages needed.

WORKDIR /app

COPY files/ /app/