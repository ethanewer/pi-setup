FROM bench-base:node-22

# The fixture ships as source plus a deterministic generator that produces the
# heavy data modules at image build time. Dependencies are baked (offline at
# trial). selfcheck.sh then proves the shipped app is in the "one enormous
# entry bundle" state the task brief describes.
WORKDIR /app
COPY files/ /app/

RUN chmod +x /app/gen/assemble.sh /app/gen/selfcheck.sh \
 && bash /app/gen/assemble.sh \
 && npm install --no-audit --no-fund \
 && bash /app/gen/selfcheck.sh \
 && rm -rf /app/gen \
 && chmod -R a+rwX /app