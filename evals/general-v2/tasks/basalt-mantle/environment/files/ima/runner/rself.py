#!/usr/bin/env python3
"""rself: run the R statistical self-test through the configured rscript.

Reads /app/ima/runner/settings.json and uses the 'rscript' field (a non-empty,
absolute path to an executable Rscript) to run a small sampling self-test.
A missing or non-executable path aborts with a nonzero exit status.
"""
import json
import os
import subprocess
import sys

CFG = '/app/ima/runner/settings.json'


def main():
    with open(CFG) as f:
        cfg = json.load(f)
    rscript = (cfg.get('rscript') or '').strip()
    if not rscript:
        print('RSELF_ERR no_rscript')
        return 2
    if not os.path.isfile(rscript) or not os.access(rscript, os.X_OK):
        print('RSELF_ERR bad_rscript %s' % rscript)
        return 3
    code = ("set.seed(11); v <- rnorm(64); "
            "cat(sprintf('R_SELFTEST mean=%.3f n=%d', mean(v), length(v)))")
    p = subprocess.run([rscript, '--vanilla', '-e', code],
                       capture_output=True, text=True)
    sys.stdout.write(p.stdout)
    sys.stderr.write(p.stderr)
    if p.returncode != 0:
        return p.returncode
    if 'R_SELFTEST' not in (p.stdout or ''):
        print('RSELF_ERR missing_marker')
        return 4
    return 0


if __name__ == '__main__':
    sys.exit(main())