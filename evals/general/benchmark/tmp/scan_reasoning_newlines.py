#!/usr/bin/env python3
"""Scan pi.txt transcripts for the pi-ai 0.84.3 token-fragment-newline symptom.

A "fragment break" is a newline inside reasoning text that is NOT explained by:
- markdown/code structure (fences, lists, tables, headers)
- a blank-line paragraph break
- a line ending in sentence punctuation before the break

Conservative: only flags dense clusters of such breaks.
"""
import json, sys, glob, re, collections

STRUCT_RE = re.compile(r'^\s*(```|[-*+] |\d+[.)] |#{1,6} |\||===|---)')

def fragment_breaks(text):
    """Return (total_fragment_breaks, lines) heuristics."""
    lines = text.split('\n')
    bad = 0
    in_fence = False
    for i in range(len(lines) - 1):
        cur, nxt = lines[i], lines[i + 1]
        if cur.strip().startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if cur.strip() == '':  # paragraph break handled by next iter
            continue
        if nxt.strip() == '':
            continue  # blank line after = normal paragraph
        if STRUCT_RE.match(nxt):
            continue
        if cur.rstrip().endswith((' ', '\t')):
            continue  # intentional wrap? treat as normal
        # break inside a flow of prose: prev line does not end with punctuation
        if cur.rstrip()[-1:] in '.!?;:)’"\'`>]':
            continue
        # next line looks like continuation (starts lowercase/space or mid-word)
        if nxt and (nxt[0] == ' ' or nxt[0].islower() or (cur and not cur[-1].isspace())):
            bad += 1
    return bad, len(lines)

def scan_file(path):
    blocks = []
    try:
        for line in open(path, errors='replace'):
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get('message')
            if not isinstance(m, dict) or m.get('role') != 'assistant':
                continue
            c = m.get('content')
            if not isinstance(c, list):
                continue
            for b in c:
                if b.get('type') == 'thinking' and b.get('text'):
                    blocks.append(b['text'])
    except OSError:
        return None
    total_chars = sum(len(t) for t in blocks)
    total_bad = 0
    worst = (0, '')
    for t in blocks:
        bad, _ = fragment_breaks(t)
        total_bad += bad
        if bad > worst[0]:
            worst = (bad, t)
    return len(blocks), total_chars, total_bad, worst

runs = sys.argv[1:] or ['deepseek-flash-run-1', 'deepseek-flash-run-2', 'deepseek-flash-run-3']
flagged = []
stats = {}
for run in runs:
    n_files = n_blocks = tot_chars = tot_bad = 0
    for path in sorted(glob.glob(f'{run}/*/agent/pi.txt')):
        r = scan_file(path)
        if r is None:
            continue
        nb, chars, bad, worst = r
        n_files += 1
        n_blocks += nb
        tot_chars += chars
        tot_bad += bad
        density = bad / chars * 1000 if chars else 0
        if chars > 2000 and density > 2.0:  # severe: >2 fragment breaks / 1k chars
            flagged.append((run, path, nb, chars, bad, round(density, 2), worst))
    stats[run] = (n_files, n_blocks, tot_chars, tot_bad)

for run, (nf, nb, tc, tb) in stats.items():
    print(f'{run}: files={nf} thinking_blocks={nb} thinking_chars={tc} '
          f'fragment_breaks={tb} density_per_1k={tb / tc * 1000 if tc else 0:.3f}')

print(f'\nSeverely flagged transcripts (>2 breaks/1k chars): {len(flagged)}')
for run, path, nb, chars, bad, dens, worst in sorted(flagged, key=lambda x: -x[5])[:20]:
    print(f'  {dens:6.2f}/1k  bad={bad:4d} chars={chars:6d} blocks={nb:3d}  {path}')
    sample = worst[1]
    # show a window around dense newline cluster
    idx = None
    lines = sample.split('\n')
    for i in range(len(lines)):
        if i + 4 < len(lines) and sum(1 for l in lines[i:i+5] if 0 < len(l.strip()) < 40) >= 4:
            idx = i
            break
    if idx is not None:
        print('    sample: ' + ' | '.join(lines[idx:idx+5]).replace('\n', '\\n')[:300])
