# jackstay-larboard — build provenance

This image was built for the task `jackstay-larboard` in the general agent
bench suite.

What is in the image:

- `/app/src`: shallow clone of the real upstream repository
  `librosa/librosa`, detached at the pinned parent commit
  `c7aa2ce80a100cd901945589437c5acc55e38739` (40 hex chars, asserted at build
  time with `test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"`). The object store
  contains exactly one commit — the fix commit derived from the mining phase is
  asserted unreachable from this clone.
- `/opt/prefix/librosa`: a pristine byte-exact copy of the *parent* package
  extracted from the pinned commit's own git objects, used by the verifier to
  prove the agent's reproduction really targets the bug.
- `/opt/golden`: the upstream project's own regression test for this bug, its
  pytest-mpl baseline image, and the test-suite conftest — extracted at build
  time from the upstream *fix* commit through a throwaway clone that is deleted
  immediately afterwards. sha256-pinned in `/opt/pins/golden.sha256`.
- Installed (pip, exact pins): numpy 2.5.3, scipy 1.18.1, numba 0.67.0,
  scikit-learn 1.9.1, joblib 1.6.0, decorator 5.3.1, soundfile 0.14.0,
  pooch 1.9.0, soxr 1.1.0, lazy_loader 0.5, msgpack 1.2.2, matplotlib 3.11.1,
  pytest 9.1.1, pytest-mpl 0.19.0, pytest-cov 7.1.0, plus `librosa` itself in
  editable mode from `/app/src`.

At image build time the bug was confirmed present in this image with these
exact pins: plotting a boolean array with the affected function attaches the
default continuous normaliser instead of a two-level one, and a pristine copy
of the package shows the same behaviour. The fixed behaviour is not present in
any part of this image except the agent's own working tree once the task is
solved; the fix commit's bytes live only in the golden-test files under
/opt/golden and were never fetched into /app/src.

Environment for the trial: `MPLBACKEND=Agg`, `PYTHONDONTWRITEBYTECODE=1`,
numeric thread pools pinned to 1 (`OMP_NUM_THREADS`, `OPENBLAS_NUM_THREADS`,
`MKL_NUM_THREADS`, `NUMEXPR_NUM_THREADS`). The trial has no network:
`task.toml` pins `network_mode = "no-network"` for the environment, the
agent phase and the verifier phase (harbor's default is public, so the
policy must be explicit), and the verifier additionally refuses to score
if it can complete a TLS handshake to github.com, raw.githubusercontent.com
or pypi.org at verifier time, so the "fix commit unreachable" property is
guarded even if the environment drifts. Everything the tests need is already
in the image; nothing needs to be fetched at trial time.