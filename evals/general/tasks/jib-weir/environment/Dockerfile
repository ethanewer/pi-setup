FROM bench-base:node-22

# bake the pinned dependency tree (no network at trial time)
WORKDIR /opt/deps
COPY deps/package.json /opt/deps/package.json
RUN npm install --no-audit --no-fund

WORKDIR /app
COPY files/ /app/
RUN mkdir -p /app/node_modules && \
    cp -a /opt/deps/node_modules/. /app/node_modules/ && \
    chmod -R a+rX /app/node_modules && \
    node --version && node_modules/.bin/tsc --version