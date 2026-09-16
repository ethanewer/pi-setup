# Working checkout: nltk/nltk (development tree)

- The NLTK source tree is cloned at `/app/src`, checked out at the exact
  revision this task was measured against, and installed in *editable* mode:
  `import nltk` (or `from nltk.tokenize import ...`) loads the code
  **straight from `/app/src/nltk`**, so any edit you make under `/app/src`
  takes effect immediately. Run a check with

      cd /app/src && python3 -c "from nltk.tokenize import NLTKWordTokenizer; print(NLTKWordTokenizer().tokenize(\"'hello'\"))"

- The NLTK data bundles this task needs (`punkt_tab`, `punkt`, `words`) are
  already installed under `/nltk_data` and found via the `NLTK_DATA` variable;
  nothing needs to be downloaded. Do not attempt to download anything and do
  not re-run `pip install` -- that can only change the environment away from
  what the acceptance expects.

- Running the project's own unit suite, from `/app/src`:

      cd /app/src && python3 -m pytest nltk/test/unit/test_tokenize.py -q

  That entire file passes on this checkout today; keep it that way.

- The checkout is a git repository (`git status`, `git diff`). Use `/tmp` for
  scratch files, and do not touch anything under the repository other than
  the tokenizer's own source.