import os
import sys

# Make the package importable directly from the source tree for these sync
# tests (the async fsx test lives outside `tests/` and imports the *installed*
# editable package instead).
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "src"))
