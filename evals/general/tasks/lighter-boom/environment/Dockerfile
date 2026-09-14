# lighter-boom: upstream-clone debugging task on nltk/nltk.
#
# The upstream repository is cloned shallow at the PARENT commit (the bug is
# present), SHA-pinned and fail-closed at build time. The project's own
# regression test for the fix is extracted from the FIX commit at build time
# into /opt/golden -- from a throwaway clone that is deleted afterwards, so
# the fix commit is never in /app/src's object store. A pristine copy of the
# parent tree is additionally installed as a real (non-editable) package into
# /opt/venv, which the verifier uses as the "pre-fix tree" when it runs the
# agent's own reproduction against both the buggy and the repaired code.
#
# Reproduced at the parent commit (bench-base:python-3.12):
#   NLTKWordTokenizer().tokenize("'hello'")      -> ["'hello", "'"]
#   NLTKWordTokenizer().tokenize("'tis a fine day'") -> ["'t", 'is', ...]
#   word_tokenize("'Hard' to tell")              -> ["'Hard", "'", 'to', 'tell']
# Verified fixed at the fix commit.

FROM bench-base:python-3.12

# git uid-1000 safety, build identity, and the system-wide safe.directory
# entry required by the suite's git gate.
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Bytecode caches would drift a rebuild's site-packages manifest (extraction
# mtimes are baked into .pyc files), so ship none and write none at trial
# time. NLTK data lives outside /usr/local (pristine for the manifest).
ENV PYTHONDONTWRITEBYTECODE=1 \
    NLTK_DATA=/nltk_data \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Main checkout: the PARENT commit (pre-fix), shallow and pinned. Resolved by
# the mining phase; the 40-hex assertion makes the build fail closed if the
# pin ever drifts. .git/info/exclude is materialised so the verifier's
# manifest can pin it (git only creates it lazily).
ARG UPSTREAM_SHA=c86229d218978628eb4e6e100ff266d2a939b7f0
RUN git clone --depth 1 https://github.com/nltk/nltk.git /app/src \
    && cd /app/src \
    && git fetch --depth 1 origin c86229d218978628eb4e6e100ff266d2a939b7f0 \
    && git checkout -q c86229d218978628eb4e6e100ff266d2a939b7f0 \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && test -z "$(git status --porcelain)" \
    && touch .git/info/exclude \
    && test -f nltk/tokenize/destructive.py \
    && grep -q "STARTING_QUOTES" nltk/tokenize/destructive.py

# Pinned dependency toolchain, resolved against this base image's interpreter
# (Python 3.12.13). Every package is pinned so a rebuild produces
# byte-identical /usr/local (the verifier pins the interpreter and
# site-packages to a build-time manifest). nltk itself declares no
# install_requires, so the editable install below pulls nothing unpinned;
# setuptools/wheel are pinned for that build.
RUN pip install setuptools==72.0.0 \
                wheel==0.44.0 \
                numpy==2.5.3 \
                pytest==9.1.1 \
                pytest-mock==3.15.1 \
                regex==2026.9.10 \
                PyYAML==6.0.3 \
                click==8.5.0 \
                tqdm==4.70.1 \
                joblib==1.6.0 \
                defusedxml==0.7.1 \
 && cd /app/src \
 && pip install -e . --no-build-isolation

# Seed the NLTK data the tokenizer tests need: punkt_tab (Punkt sentence
# tokenizer used by word_tokenize), punkt and words (used by other tests in
# nltk/test/unit/test_tokenize.py). No test in the selected slice downloads
# anything at run time.
RUN python3 -c "import nltk; nltk.download('punkt_tab', download_dir='/nltk_data', quiet=True)" \
 && python3 -c "import nltk; nltk.download('punkt',   download_dir='/nltk_data', quiet=True)" \
 && python3 -c "import nltk; nltk.download('words',   download_dir='/nltk_data', quiet=True)"

# Extract the project's own regression test from the FIX commit, in a
# throwaway clone that is deleted before the layer commits. This keeps the
# fix commit out of /app/src's object store (an agent must not be able to
# recover the patch with `git show`), and keeps upstream bytes out of the
# task tree itself.
ARG FIX_SHA=1929bf9e365faa9e476b3abbccb72a74351d647e
RUN mkdir -p /tmp/golden-src /opt/golden \
    && git clone --depth 1 https://github.com/nltk/nltk.git /tmp/golden-src \
    && cd /tmp/golden-src \
    && git fetch --depth 1 origin 1929bf9e365faa9e476b3abbccb72a74351d647e \
    && git show 1929bf9e365faa9e476b3abbccb72a74351d647e:nltk/test/unit/test_tokenize.py > /opt/golden/test_tokenize.py \
    && test -s /opt/golden/test_tokenize.py \
    && grep -q "test_word_tokenize_opening_single_quote_padding" /opt/golden/test_tokenize.py \
    && cd / \
    && rm -rf /tmp/golden-src

# Pre-fix reference tree for the verifier. The editable install's PEP 660
# finder maps "nltk" to /app/src unconditionally, so a second, REAL install of
# the pristine parent tree into its own venv is what the verifier uses to run
# the agent's reproduction against the buggy code. The venv never sees the
# system editable finder (its sys.path contains only the venv site-packages).
RUN cp -a /app/src /tmp/pristine-src \
    && rm -rf /tmp/pristine-src/.git \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install setuptools==72.0.0 \
                                  wheel==0.44.0 \
                                  numpy==2.5.3 \
                                  regex==2026.9.10 \
                                  PyYAML==6.0.3 \
                                  click==8.5.0 \
                                  tqdm==4.70.1 \
                                  joblib==1.6.0 \
                                  defusedxml==0.7.1 \
    && /opt/venv/bin/pip install -q --no-build-isolation /tmp/pristine-src \
    && rm -rf /tmp/pristine-src \
    && cd / && /opt/venv/bin/python -c "import nltk.tokenize.destructive as d; assert d.__file__.startswith('/opt/venv/'), d.__file__"

# Warm baseline: the project's own existing unit slice (the tokenizer suite
# that the fix touches) must already be green on the pristine parent tree; it
# is what the acceptance also asserts after the agent's change. A broken pin
# or missing data fails the build, not the trial.
RUN cd /app/src \
    && python3 -m pytest -q -p no:cacheprovider nltk/test/unit/test_tokenize.py 2>&1 \
       | tee /tmp/baseline.log \
       | grep -q "78 passed" \
    && rm -f /tmp/baseline.log

# Timestamp pyc caches embed the source file's extraction mtime, so a rebuild
# of the same Dockerfile at a different wall time produces different
# site-packages .pyc bytes and a manifest recorded from an earlier build can
# never match. Ship none of them: bytecode is derived from the pinned
# sources, so it is not part of the deliverable, and the verifier's
# usrlocal-manifest "new file" check catches any .pyc an agent plants at
# trial time (PYTHONDONTWRITEBYTECODE=1 means an honest run never recreates
# these caches either).
RUN find /usr/local/lib/python3.12/site-packages -type d -name __pycache__ -prune -exec rm -rf {} + \
    && find /usr/local/lib/python3.12/site-packages -type f -name '*.pyc' -delete

WORKDIR /app

# One CPU budget; keep any extension libs single-threaded.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

COPY files/ /app/