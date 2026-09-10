# gantry-ember — ship the dutywheel project with a flaky rotation test.
#
# The fixture is a real, self-authored Python project (multi-module
# package, pyproject, sample roster, 14-test pytest suite, git history).
# The rotation module's tie-break uses the interpreter's per-process
# random hash() and ignores the previous on-call member, so one test in
# the suite fails ~1/15 of full runs. The verifier pins 40 seeds that
# deterministically trigger the pre-fix failure (negative control), then
# requires 40/40 green on the agent's fixed tree and that two hidden
# source mutants still make the suite go red.
FROM bench-base:python-3.12

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pytest==9.1.1 setuptools==84.0.0 wheel==0.48.0

WORKDIR /app

COPY files/ /app/

# Build a real repository with history, committed incrementally so the
# agent can use git log/blame. The trial may run as a non-root uid, so
# record a system-wide safe.directory and a build committer identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "wheel@dutywheel.local" \
 && git config --system user.name "dutywheel build" \
 && cd /app/dutywheel \
 && git init -q -b main \
 && git add pyproject.toml README.md .gitignore dutywheel/__init__.py \
 && git commit -qm "scaffold dutywheel package" \
 && git add dutywheel/crew.py samples/engineering.json \
 && git commit -qm "crew roster loader with validation" \
 && git add dutywheel/rotation.py \
 && git commit -qm "rotation wheel with availability-weighted selection" \
 && git add dutywheel/schedule.py dutywheel/cli.py dutywheel/__main__.py \
 && git commit -qm "weekly schedule renderer and CLI" \
 && git add tests \
 && git commit -qm "test suite for crew, rotation and schedule" \
 && pip install --no-cache-dir -e /app/dutywheel --no-build-isolation \
 && python3 -c "import ast,sys; [ast.parse(open(p).read()) for p in ['dutywheel/rotation.py','dutywheel/crew.py','dutywheel/schedule.py','dutywheel/cli.py','tests/test_rotation.py','tests/test_crew.py','tests/test_schedule.py']]; print('fixture syntax OK')"