FROM bench-base:python-3.12

# ds-mistral-manifest — manifest-merge / values-precedence chart engine bench.
# Ships one visible chart under /app/charts and visible values files under
# /app/overrides. The agent authors the CLI deliverable /app/render_chart.py
# and produces /app/rendered from the documented command. Python 3.12 stdlib
# only; no runtime network.

WORKDIR /app

COPY files/ /app/