# Gale Vault Inbox — web-http-contract task image.
# Lean: Flask (REST), Playwright + headless Chromium (stored-XSS render check).
# No GPU/X/systemd. Build completes in ~2.5min in the sandbox.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Flask + Playwright + headless Chromium (--with-deps pulls the apt libs the
# browser needs; corporate CA is already baked into the bench base image).
RUN pip install --no-cache-dir flask playwright \
 && python3 -m playwright install chromium --with-deps \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -c "from playwright.sync_api import sync_playwright; \
                 p=sync_playwright().start(); b=p.chromium.launch(); b.close(); p.stop(); \
                 print('chromium-headless-ok')"

# Where the verifier writes the numeric reward.
RUN mkdir -p /logs/verifier