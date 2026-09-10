# escutcheon-stack — Terraform adoption of hand-managed configuration.
#
# Ships a pinned Terraform 1.9.8 binary plus an offline filesystem provider
# mirror (hashicorp/local, hashicorp/null) so that init/plan/apply all run with
# no network at trial time. The agent authors /app/stack/deploy.sh, which adopts
# pre-existing on-disk files under Terraform management and adds a manifest as a
# second managed resource.

FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
# Numeric routines in provider tooling are run single-threaded (cpus=1).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
# Point every terraform invocation at the offline filesystem provider mirror.
ENV TF_CLI_CONFIG_FILE=/opt/tfcli/.terraformrc

# --- Terraform 1.9.8 (pinned exact binary, verified reachable at build time) ---
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/tf/bin && \
    curl -fsSL -o /tmp/tf.zip \
        https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip && \
    cd /opt/tf/bin && python3 -c "import zipfile;zipfile.ZipFile('/tmp/tf.zip').extractall('.')" && \
    chmod +x /opt/tf/bin/terraform && rm -f /tmp/tf.zip

# --- offline provider mirror (hashicorp/local + hashicorp/null) ---
# Seed a throwaway module, let terraform resolve + download, then mirror it so
# every later init/plan/apply runs entirely offline against the mirror.
RUN mkdir -p /opt/tf/seed && cd /opt/tf/seed && \
    printf 'terraform {\n  required_providers {\n    local = { source = "hashicorp/local" }\n    null  = { source = "hashicorp/null"  }\n  }\n}\n' > seed.tf && \
    /opt/tf/bin/terraform init -input=false >/dev/null 2>&1 && \
    /opt/tf/bin/terraform providers mirror /opt/tf-mirror >/dev/null 2>&1 && \
    rm -rf /opt/tf/seed

# --- CLI config pointing terraform at the mirror (offline) ---
RUN mkdir -p /opt/tfcli && printf 'provider_installation {\n  filesystem_mirror {\n    path    = "/opt/tf-mirror"\n    include = ["registry.terraform.io/hashicorp/*"]\n  }\n  direct {\n    exclude = ["registry.terraform.io/hashicorp/*"]\n  }\n}\n' > /opt/tfcli/.terraformrc && \
    chmod 644 /opt/tfcli/.terraformrc

ENV PATH=/opt/tf/bin:$PATH

WORKDIR /app
COPY files/ /app/

# Keep the deliverable directory writable regardless of which uid the harness
# runs the agent under.
RUN chmod 777 /app && chmod -R a+rX /app

CMD ["/bin/bash"]
