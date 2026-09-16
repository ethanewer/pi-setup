FROM bench-base:python-3.12

WORKDIR /app

# The whole fixture is static: the intake service fixture, the release
# bundles (1.0.2 / 2.0.1), the deploy tool, the environment registry and the
# pre-existing live installs of both environments. Nothing needs a network
# at build time or at trial time.
COPY files/ /app/