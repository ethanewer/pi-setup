"""Entry point for ``python3 -m quaydoc``."""

import sys

from quaydoc.cli import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
