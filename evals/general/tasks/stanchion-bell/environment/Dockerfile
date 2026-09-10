# stanchion-bell — Lanternwell Clinic accessibility remediation.
#
# A self-authored React 18 site (four pages from shared components) ships with
# eight real accessibility defects. The agent must remediate the app so the
# verifier's axe-core run over jsdom-rendered pages (three of them unseen)
# reports zero moderate+ violations and the targeted focus/ARIA checks pass.
#
# The trial container has no network, so React, jsdom, axe-core, vitest and
# @testing-library/react are pinned and installed at build time. The working
# tree is copied in and turned into a real git repository by
# scripts/make_repo.sh, which is why the safe.directory wildcard and a build
# identity are configured before it runs.

FROM bench-base:node-22

RUN git config --system --add safe.directory '*' && \
    git config --system user.email "build@lanternwell.local" && \
    git config --system user.name "Lanternwell build"

WORKDIR /app
COPY files/ /app/
RUN bash /app/scripts/make_repo.sh

RUN npm install --no-audit --no-fund --loglevel=error && \
    rm -rf /root/.npm

ENV CI=true