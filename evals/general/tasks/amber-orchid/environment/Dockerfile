# Merkstock Indexer -- web-http-contract task image.
# Flask (REST service) + Playwright headless Chromium (comment-render XSS check).
# No GPU/X/systemd/docker. Build completes in ~2.5-3min in the sandbox.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Flask (service) + Playwright with headless Chromium. The Chromium binary and
# its apt dependencies are needed to honestly exercise "auto-executes in a
# headless browser". Corporate CA is already baked into the bench base image.
RUN pip install --no-cache-dir flask playwright \
 && python3 -m playwright install chromium --with-deps \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -c "from playwright.sync_api import sync_playwright; \
                 p=sync_playwright().start(); b=p.chromium.launch(); b.close(); p.stop(); \
                 print('chromium-headless-ok')"

RUN mkdir -p /logs/verifier