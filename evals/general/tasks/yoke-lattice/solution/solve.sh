#!/usr/bin/env bash
# Oracle for yoke-lattice: installs the real local runner and a valid
# 3-job workflow with a dependency graph, then proves the pair works by
# executing the pipeline on the delivered workflow. Never reads /tests.
set -euo pipefail

mkdir -p /app/.github/workflows

cp /solution/runner.py /app/run_pipeline.py
chmod +x /app/run_pipeline.py

cat > /app/run_pipeline.sh <<'SH'
#!/usr/bin/env bash
# Local GitHub Actions runner (deliverable). All logic lives in the
# adjacent Python module; see the task instruction for the contract.
exec python3 /app/run_pipeline.py "$@"
SH
chmod +x /app/run_pipeline.sh

cp /solution/ci.yml /app/.github/workflows/ci.yml

# Self-test the delivered pair on the delivered workflow. A non-zero exit
# here fails the oracle, which is the point: the deliverables must work.
/app/run_pipeline.sh /app/.github/workflows/ci.yml /app/.run/oracle \
    --workspace /app --ref refs/heads/main --event push

echo "oracle: /app/run_pipeline.sh and /app/.github/workflows/ci.yml delivered and executed"