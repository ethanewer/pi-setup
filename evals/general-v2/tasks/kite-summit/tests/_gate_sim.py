#!/usr/bin/env python3
"""Independent evaluator for /app/gate_net.txt (does not trust gate_validate.py).

Usage: python3 _gate_sim.py <inputs_file>
Prints PASS and exits 0 only if the network matches the isqrt+Fibonacci reference
for every input. This reference/structure is duplicated here on purpose so the
grader does not depend on the agent-authored validator.
"""
import math
import sys

MASK = 0xFFFFFFFF
NET = '/app/gate_net.txt'


def fib_mod(n):
    def fd(k):
        if k == 0:
            return (0, 1)
        a, b = fd(k >> 1)
        c = (a * ((2 * b - a) & MASK)) & MASK
        d = (a * a + b * b) & MASK
        if k & 1:
            return (d, (c + d) & MASK)
        return (c, d)
    return fd(n)[0]


def reference(x):
    return fib_mod(math.isqrt(x))


def parse_net(path):
    nodes = []
    out = None
    n_cap = None
    for raw in open(path):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        head = line.split()
        if line[0].isdigit():
            if len(head) < 3 or head[1] != '=':
                return None, None, None
            nodes.append((head[2], [int(h) for h in head[3:]]))
        elif head[0] == 'VERSION' and head[1] != '1':
            return None, None, None
        elif head[0] == 'BITS' and head[1] != '32':
            return None, None, None
        elif head[0] == 'NODES':
            n_cap = int(head[1])
        elif head[0] == 'OUTPUT':
            out = int(head[1])
    return nodes, out, n_cap


def run_net(nodes, out, x):
    vals = [0] * len(nodes)
    for i, (op, args) in enumerate(nodes):
        if op == 'IN':
            vals[i] = x
        elif op == 'CONST':
            vals[i] = args[0]
        elif op == 'ADD':
            vals[i] = (vals[args[0]] + vals[args[1]]) & MASK
        elif op == 'SUB':
            vals[i] = (vals[args[0]] - vals[args[1]]) & MASK
        elif op == 'MUL':
            vals[i] = (vals[args[0]] * vals[args[1]]) & MASK
        elif op == 'SHL':
            vals[i] = (vals[args[0]] << args[1]) & MASK
        elif op == 'SHR':
            vals[i] = vals[args[0]] >> args[1]
        elif op == 'AND':
            vals[i] = vals[args[0]] & vals[args[1]]
        elif op == 'OR':
            vals[i] = vals[args[0]] | vals[args[1]]
        elif op == 'XOR':
            vals[i] = vals[args[0]] ^ vals[args[1]]
        elif op == 'NOT':
            vals[i] = (~vals[args[0]]) & MASK
        elif op == 'MUX':
            vals[i] = vals[args[1]] if vals[args[0]] else vals[args[2]]
        elif op == 'ULT':
            vals[i] = 1 if vals[args[0]] < vals[args[1]] else 0
        else:
            raise ValueError(f'unknown op {op}')
    if out is None or out < 0 or out >= len(vals):
        raise ValueError(f'bad OUTPUT node {out}')
    return vals[out]


def load_inputs(path):
    vals = []
    for raw in open(path):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        vals.append(int(line, 0))
    if not vals:
        raise ValueError('empty inputs file')
    for v in vals:
        if v < 0 or v > 0xFFFFFFFF:
            raise ValueError(
                f'input {v} outside documented domain 0 <= x <= 2^32-1')
    return vals


def main():
    if len(sys.argv) < 2:
        print('usage: _gate_sim.py <inputs_file>')
        return 2
    try:
        nodes, out, n_cap = parse_net(NET)
        if nodes is None:
            print('FAIL: could not parse gate_net.txt')
            return 1
        xvals = load_inputs(sys.argv[1])
        bad = 0
        for x in xvals:
            got = run_net(nodes, out, x)
            exp = reference(x)
            if got != exp:
                bad += 1
                if bad <= 5:
                    print(f'FAIL x={x} expected={exp} got={got}')
        if bad:
            print(f'FAIL ({bad} mismatches over {len(xvals)} inputs)')
            return 1
        print(f'PASS ({len(xvals)} inputs over net with {len(nodes)} nodes)')
        return 0
    except Exception as e:  # noqa: BLE001
        print(f'FAIL internal error: {e!r}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
