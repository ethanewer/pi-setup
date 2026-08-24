#!/bin/bash
set -euo pipefail

# Move line 2 ("beta") to after the final line using normal-mode vim commands.
vim /app/lines.txt -c 'normal j' -c 'normal dd' -c 'normal j' -c 'normal p' -c 'wq!'