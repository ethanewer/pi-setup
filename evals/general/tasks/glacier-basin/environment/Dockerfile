FROM bench-base:python-3.12

# glacier-basin: mini test-harness bench. Ships a v1 sequential runner and a
# visible suite manifest. The agent extends the runner per the instruction
# contract (LPT duration sharding, bail-on-failure, CTRF-like reports) and
# produces the run report for the visible suite. Python stdlib only; no network.
WORKDIR /app

COPY files/ /app/

# Mark the shipped runner readable/executable-by-convention (plain 0644 is fine;
# the agent drives it with `python3 /app/harness/runner.py ...`).
RUN chmod 0644 /app/harness/runner.py