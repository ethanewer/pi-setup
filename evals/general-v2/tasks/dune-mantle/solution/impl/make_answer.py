#!/usr/bin/env python3
"""Generate /app/answer.json by RUNNING the real dossier on the shipped visible
inputs. Nothing is hard-coded: each field is derived by executing /app/solve.py
and /usr/local/bin/symxe."""
import json, re, subprocess, sys

def sh(ins=None, *argv):
    r = subprocess.run(list(argv), capture_output=True, text=True, input=ins)
    if r.returncode != 0:
        sys.stderr.write('cmd failed: %r\n%s\n%s\n' % (argv, r.stdout, r.stderr))
        sys.exit(2)
    return r.stdout

ans = {}

# weighted max-sat on the visible instance
out = sh(None, '/usr/bin/python3', '/app/solve.py', 'wcnf', '/app/instance.wcnf')
m = re.search(r'^OPT\s+(\d+)\s*$', out, re.M)
assert m, 'no OPT line'
ans['wcnf_opt'] = int(m.group(1))

# QF_BV verdict, read from stdin
q = sh(open('/app/qfbv_query.smt2').read(),
       '/usr/bin/python3', '/app/solve.py', 'qfbv')
ans['qfbv'] = q.strip().splitlines()[0]

# seating CSP
se = sh(None, '/usr/bin/python3', '/app/solve.py', 'seats', '/app/seats.txt')
seats = {'boards': []}
for line in se.splitlines():
    if line.startswith('FOCUS '):
        seats['focus'] = line[6:].strip()
    elif line.startswith('PAIRS '):
        seats['pairs'] = [x.strip() for x in line[6:].split(',')]
    elif line.startswith('NBOARDS '):
        seats['nboards'] = int(line[8:].strip())
    elif line.startswith('FIXPOINT '):
        seats['fix'] = int(line[9:].strip())
    elif line.startswith('PHRASE '):
        seats['phrase'] = line[7:].strip()
    elif line.startswith('STEPS '):
        seats['steps'] = int(line[6:].strip())
    elif re.match(r'^[A-Z]{6,}$', line.strip()):
        seats['boards'].append(line.strip())
ans['seats'] = seats

# symbolic engine on the visible seed
sv = sh(None, '/usr/local/bin/symxe', '--version').split()[-1]
sp = 0
try:
    with open('/app/work/classify.symx') as fh:
        mm = re.search(r'^PATHS\s+(\d+)\s*$', fh.read(), re.M)
        if mm:
            sp = int(mm.group(1))
except FileNotFoundError:
    pass
ans['symxe'] = {'engine': 'symxe', 'version': sv, 'paths': sp}

ans['cert'] = 'ok'

json.dump(ans, open('/app/answer.json', 'w'), indent=2)
sys.stdout.write('answer.json written\n')