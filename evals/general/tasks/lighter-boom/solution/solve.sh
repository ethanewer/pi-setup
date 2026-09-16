#!/bin/bash
# Oracle for lighter-boom: fixes the NLTKWordTokenizer opening-quote padding
# rule (issue #3687) in the pinned checkout at /app/src, exactly as a
# competent agent would, then writes the /app/reproduce.py deliverable (a
# genuine reproduction that fails on the pre-fix tree and passes post-fix)
# and proves the whole contract inside the image: reproduction, the
# project's own regression test, and the project's own tokenizer suite.
# It NEVER reads the /tests directory.
set -euo pipefail

SRC=/app/src
FIXED="$SRC/nltk/tokenize/destructive.py"

# 1) Write the deliverable reproduction: assertions describe the CORRECT
#    behavior, so the file fails on the buggy tree and passes once fixed.
cat > /app/reproduce.py <<'PY'
from nltk.tokenize import NLTKWordTokenizer

TOKENIZER = NLTKWordTokenizer()

# 1. A quoted multi-letter word mid-sentence: the opening quote must be its
# own token, not glued to the word.
toks = TOKENIZER.tokenize("'hello'")
assert toks == ["'", "hello", "'"], toks

# 2. A quoted multi-letter word starting the text: same contract.
toks = TOKENIZER.tokenize("'Hard' to tell")
assert toks == ["'", "Hard", "'", "to", "tell"], toks

# 3. A word beginning with an opening quote must not be split in two.
toks = TOKENIZER.tokenize("'tis a fine day'")
assert toks == ["'", "tis", "a", "fine", "day", "'"], toks

# 4. Intra-word apostrophes and clitic contractions stay intact.
toks = TOKENIZER.tokenize("o'clock")
assert toks == ["o'clock"], toks
toks = TOKENIZER.tokenize("O'Connor")
assert toks == ["O'Connor"], toks
toks = TOKENIZER.tokenize("It's more'n enough.")
assert toks == ["It", "'s", "more", "'n", "enough", "."], toks

print("reproduce.py: all tokenization expectations hold")
PY

# 2) Apply the fix: the opening-quote padding rule must fire before a word of
#    any length, not just before a single letter, while the clitic lookahead
#    and the (?<!\w) guard keep contractions and intra-word apostrophes
#    untouched.
python3 - "$FIXED" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
old = '''        (re.compile(r"(?i)(\\')(?!re|ve|ll|m|t|s|d|n)(\\w)\\b", re.U), r"\\1 \\2"),'''
new = '''        (
            re.compile(r"(?i)(?<!\\w)(\\')(?!(?:re|ve|ll|m|t|s|d|n)\\b)(?=\\w)", re.U),
            r"\\1 ",
        ),'''
assert old in source, "destructive.py does not match the pinned checkout; aborting"
path.write_text(source.replace(old, new))
print("patched", path)
PY

# 3) The deliverable reproduction must pass on the repaired tree.
cd /tmp
PYTHONPATH=$SRC python3 /app/reproduce.py

# 4) The project's own regression test for this bug must pass.
cd "$SRC"
PYTHONPATH=$SRC python3 -m pytest -q -o addopts= -p no:cacheprovider \
  /opt/golden/test_tokenize.py::TestTokenize::test_word_tokenize_opening_single_quote_padding

# 5) The project's own existing tokenizer suite must stay green.
cd "$SRC"
PYTHONPATH=$SRC python3 -m pytest -q -p no:cacheprovider \
  nltk/test/unit/test_tokenize.py

echo "lighter-boom oracle done"