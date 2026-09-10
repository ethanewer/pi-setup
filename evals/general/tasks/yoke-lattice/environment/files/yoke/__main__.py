"""Allow `python -m yoke` from a checkout of this repository."""

import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main())