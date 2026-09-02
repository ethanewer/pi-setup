#!/usr/bin/env python3
"""spire: the profiling runner.

Before every script under /app is executed under cProfile, this runner reads
/app/ima/runner/settings.json and looks up the interpreter shim in the
'python_shim' field. The field must contain a non-empty, absolute path to an
existing, executable Python interpreter. The runner then spawns that
interpreter with ``-m cProfile -s cumtime <target>``.
"""
import json
import os
import subprocess
import sys

CFG = '/app/ima/runner/settings.json'


def main():
    with open(CFG) as f:
        cfg = json.load(f)
    shim = (cfg.get('python_shim') or '').strip()
    if not shim:
        print('SPIRE_ERR missing_shim')
        return 2
    if not os.path.isfile(shim) or not os.access(shim, os.X_OK):
        print('SPIRE_ERR bad_shim %s' % shim)
        return 3
    target = sys.argv[1] if len(sys.argv) > 1 else '/app/ima/runner/target_probe.py'
    p = subprocess.run([shim, '-m', 'cProfile', '-s', 'cumtime', target],
                       capture_output=True, text=True)
    sys.stdout.write(p.stdout)
    sys.stderr.write(p.stderr)
    if p.returncode != 0:
        print('SPIRE_ERR run_%d' % p.returncode)
        return p.returncode
    print('SPIRE_OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())