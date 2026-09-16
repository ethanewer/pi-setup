# Build / test FAQ for this container

- spaCy 3.8.11 is installed **editable** from `/app/src`
  (`import spacy` -> `/app/src/spacy`). No network at trial time.
- Editing a `.pyx` (Cython) source does NOT change behaviour until the
  extension module is recompiled:
  ```bash
  cd /app/src
  python3 setup.py build_ext --inplace
  ```
  If behaviour looks stale after an edit, delete the affected `spacy/*.so`
  binaries first, then rebuild.
- The project's test suite runs offline with:
  ```bash
  cd /app/src && python3 -m pytest <path> -q
  ```
- Everything (compiler, runtime deps, test deps) is preinstalled; do not
  install anything.
- Do not touch `/opt`, `/tests`, `/solution`. Do not move `HEAD` off the
  pinned commit.