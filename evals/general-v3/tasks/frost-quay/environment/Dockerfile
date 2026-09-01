FROM bench-base:python-3.12

WORKDIR /app

# The platform preinstalls the pinned ML toolchain. This is the immutable
# baseline the export bench depends on: provisioning/agent work must NEVER
# upgrade, downgrade, or reinstall these two distributions.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1

# Bench fixtures: the tiny offline encoder checkpoint, the (deprecated) legacy
# downgrade bundle, and a build-time-only generator.
COPY files/ /app/

# Materialize the visible encoder checkpoint with the pinned toolchain and
# capture the exact installed versions as the pristine baseline manifest.
# The generator is removed so the live container carries only the artifacts.
RUN python3 /app/gen_model.py \
 && rm -f /app/gen_model.py \
 && rm -rf /app/__pycache__ \
 && python3 -c "import torch, transformers, json; json.dump({'torch': torch.__version__, 'transformers': transformers.__version__}, open('/app/toolchain_pins.json', 'w'), indent=2, sort_keys=True)"
