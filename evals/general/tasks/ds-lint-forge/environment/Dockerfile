# ds-lint-forge — linter rule engineering on the lintkit minipy engine.
#
# Ships the engine (tokenizer + tiny AST + CLI skeleton with line-scoped
# suppression only), the fixed forbidden-name config and visible examples.
# The agent must author the three rule plugins, extend suppression (region +
# next-statement forms) and add the incremental findings cache — all under
# /app.  The verifier runs the deliverable CLI on hidden minipy sources and
# independently recomputes the expected findings.

FROM bench-base:python-3.12

WORKDIR /app

# Fixed engine infrastructure (never the answer): lexer, parser, AST,
# structural analysis, and the lint CLI *skeleton* that the agent extends.
COPY files/lintkit/ /app/lintkit/

# Fixed configuration read by the forbid-call rule plugin.
COPY files/rules/ /app/rules/

# Visible examples the agent may lint to self-check.
COPY files/examples/ /app/examples/

RUN python3 -m compileall -q /app/lintkit /app/rules /app/examples || true