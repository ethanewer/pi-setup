# vine-delta runtime image.
# Pure-Python algorithmic task; python3 is already in the bench base, so the
# image stays lean (no apt installs, no GPU/X/systemd, no network at runtime).
FROM bench-base:python-3.12

WORKDIR /app

# Nothing is pre-seeded in /app: the agent authors /app/solve.py itself, and
# the oracle (solution/solve.sh) copies its own implementation in and runs it.