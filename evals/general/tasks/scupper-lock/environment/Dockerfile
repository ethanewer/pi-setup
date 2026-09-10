FROM bench-base:node-22

# scupper-lock: React 18 component workspace (node 22 base, jsdom testing).
# The npm packages are baked into the image because the trial container has
# no network access; react, react-dom, @testing-library/react, jsdom, vitest
# and typescript are pinned to exact versions in package.json.
WORKDIR /app

COPY files/ /app/

RUN npm install --no-audit --no-fund --loglevel=error \
    && rm -rf /tmp/npm-cache

ENV CI=true