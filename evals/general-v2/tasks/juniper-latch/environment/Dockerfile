# juniper-latch: sigdeck hotfix environment
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Smoke-check the package imports and the runner runs end-to-end.
RUN python3 -c "import sigdeck.runner, sigdeck.windowing" \
 && python3 -m sigdeck.runner /app/input.csv /tmp/smoke.json
