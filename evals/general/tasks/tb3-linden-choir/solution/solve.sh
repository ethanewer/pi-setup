#!/bin/bash
#
# tb3-linden-choir oracle. Authors the analyzer CLI /app/analyze.py (pure
# stdlib, deterministic), runs it on the visible fixture to produce the
# deliverable /app/analysis.json, and self-checks the analysis against the
# documented expected values of the visible score. Never reads /tests.
set -euo pipefail

cat > /app/analyze.py <<'PYEOF'
#!/usr/bin/env python3
"""linden-choir analyzer. Pure stdlib, deterministic.

Usage: python3 analyze.py <score.json> <analysis.json>
Exits 0 and writes the analysis JSON on success; on any malformed input it
prints a short message to stderr, exits non-zero, and does not create the
output file.
"""
import json
import re
import sys

NOTE_RE = re.compile(r'^([A-G])([#b]?)([0-9])$')
KEY_RE = re.compile(r'^([A-G])([#b]?)(maj|min)$')
SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}

_OFF3 = {'major': 4, 'minor': 3, 'diminished': 3}
_OFF5 = {'major': 7, 'minor': 7, 'diminished': 6}


def midi(note):
    m = NOTE_RE.match(note)
    if not m:
        raise ValueError('malformed note %r' % note)
    letter, acc, octv = m.group(1), m.group(2), int(m.group(3))
    pc = (SEMI[letter] + (1 if acc == '#' else -1 if acc == 'b' else 0)) % 12
    return (octv + 1) * 12 + pc


def parse_key(key):
    m = KEY_RE.match(key)
    if not m:
        raise ValueError('malformed key %r' % key)
    letter, acc, mode = m.group(1), m.group(2), m.group(3)
    tonic = (SEMI[letter] + (1 if acc == '#' else -1 if acc == 'b' else 0)) % 12
    return tonic, mode


def build_pool(key):
    """Returns (tonic_pc, pool) following the documented triad tables."""
    tonic, mode = parse_key(key)
    pool = []
    if mode == 'maj':
        scale = [(tonic + iv) % 12 for iv in (0, 2, 4, 5, 7, 9, 11)]
        numerals = ('I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii\u00b0')
        qualities = ('major', 'minor', 'minor', 'major', 'major', 'minor', 'diminished')
        for d in range(7):
            t = {scale[d], scale[(d + 2) % 7], scale[(d + 4) % 7]}
            q = qualities[d]
            pool.append({'pcs': t, 'roman': numerals[d], 'quality': q,
                         'root': scale[d], 'third': (scale[d] + _OFF3[q]) % 12,
                         'fifth': (scale[d] + _OFF5[q]) % 12, 'prio': d})
    else:
        n = [(tonic + iv) % 12 for iv in (0, 2, 3, 5, 7, 8, 10)]
        r7 = (tonic + 11) % 12
        entries = (
            ({n[0], n[2], n[4]}, 'i', 'minor', n[0]),
            ({n[1], n[3], n[5]}, 'ii\u00b0', 'diminished', n[1]),
            ({n[2], n[4], n[6]}, 'III', 'major', n[2]),
            ({n[3], n[5], n[0]}, 'iv', 'minor', n[3]),
            ({n[4], r7, n[1]}, 'V', 'major', n[4]),
            ({n[4], n[6], n[1]}, 'v', 'minor', n[4]),
            ({n[5], n[0], n[2]}, 'VI', 'major', n[5]),
            ({n[6], n[1], n[3]}, 'VII', 'major', n[6]),
            ({r7, n[1], n[3]}, 'vii\u00b0', 'diminished', r7),
        )
        for prio, (pcs, roman, quality, root) in enumerate(entries):
            pool.append({'pcs': pcs, 'roman': roman, 'quality': quality,
                         'root': root, 'third': (root + _OFF3[quality]) % 12,
                         'fifth': (root + _OFF5[quality]) % 12, 'prio': prio})
    return tonic, pool


def analyze_chord(chord, pool):
    notes = sorted(chord['notes'], key=midi)
    pcs = frozenset(midi(n) % 12 for n in chord['notes'])
    bass = midi(notes[0]) % 12
    cands = [t for t in pool if t['pcs'] <= pcs]
    if not cands:
        raise ValueError('chord at beat %s matches no diatonic triad' % chord['beat'])
    bass_roots = [t for t in cands if t['root'] == bass]
    if len(bass_roots) == 1:
        chosen = bass_roots[0]
    elif bass_roots:
        chosen = min(bass_roots, key=lambda t: (t['root'], t['prio']))
    else:
        chosen = min(cands, key=lambda t: (t['root'], t['prio']))
    if chosen['root'] == bass:
        inv = ''
    elif chosen['third'] == bass:
        inv = '6'
    elif chosen['fifth'] == bass:
        inv = '64'
    else:
        inv = ''
    roman = chosen['roman'] + ('6' if inv == '6' else '64' if inv == '64' else '')
    return roman, chosen['quality'], inv


DOM = ('V', 'V6', 'vii\u00b0', 'vii\u00b06')
TON = ('I', 'I6', 'i', 'i6')


def cadence_for(prev, cur, soprano_pc, tonic_pc):
    if prev in DOM and cur in TON:
        if prev == 'V' and cur in ('I', 'i') and soprano_pc == tonic_pc:
            return 'PAC'
        return 'IAC'
    if cur == 'V':
        return 'HC'
    if prev in ('IV', 'iv') and cur in ('I', 'i'):
        return 'PLAGAL'
    return None


def analyze(score):
    if not isinstance(score, dict) or 'key' not in score or 'chords' not in score:
        raise ValueError('score must have "key" and "chords"')
    tonic, pool = build_pool(score['key'])
    chords = score['chords']
    if not isinstance(chords, list):
        raise ValueError('"chords" must be a list')
    results = []
    for ch in chords:
        if (not isinstance(ch, dict) or 'beat' not in ch
                or 'duration' not in ch or 'notes' not in ch):
            raise ValueError('chord missing beat/duration/notes')
        roman, quality, inv = analyze_chord(ch, pool)
        results.append({'beat': ch['beat'], 'roman': roman, 'quality': quality,
                        'inversion': inv, 'cadence': None})
    last = len(chords) - 1
    for i in range(1, len(chords)):
        if i != last and not (chords[i]['duration'] >= 2):
            continue
        notes = sorted(chords[i]['notes'], key=midi)
        soprano_pc = midi(notes[-1]) % 12
        results[i]['cadence'] = cadence_for(results[i - 1]['roman'],
                                            results[i]['roman'], soprano_pc, tonic)
    parallels = []
    for i in range(len(chords) - 1):
        a = sorted(chords[i]['notes'], key=midi)
        b = sorted(chords[i + 1]['notes'], key=midi)
        n = min(len(a), len(b))
        for j in range(n):
            for k in range(j + 1, n):
                da = (midi(a[k]) - midi(a[j])) % 12
                db = (midi(b[k]) - midi(b[j])) % 12
                if da == db == 7:
                    parallels.append({'beats': [chords[i]['beat'], chords[i + 1]['beat']],
                                      'interval': 'P5'})
                elif (da == db == 0 and midi(a[k]) != midi(a[j])
                      and midi(b[k]) != midi(b[j])):
                    parallels.append({'beats': [chords[i]['beat'], chords[i + 1]['beat']],
                                      'interval': 'P8'})
    return {'chords': results, 'parallels': parallels}


def main(argv):
    if len(argv) != 3:
        print('usage: analyze.py <score.json> <analysis.json>', file=sys.stderr)
        return 1
    score_path, out_path = argv[1], argv[2]
    try:
        with open(score_path, 'r', encoding='utf-8') as fh:
            score = json.load(fh)
        analysis = analyze(score)
        with open(out_path, 'w', encoding='utf-8') as fh:
            json.dump(analysis, fh, indent=2)
            fh.write('\n')
        return 0
    except Exception as exc:
        print('analyze: %s' % exc, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/analyze.py

python3 /app/analyze.py /app/score.json /app/analysis.json

# Self-check: the visible analysis must match the documented values exactly.
python3 - <<'PY'
import json
with open('/app/analysis.json') as fh:
    a = json.load(fh)
romans = [c['roman'] for c in a['chords']]
assert romans == ['I', 'ii6', 'V', 'I6', 'IV', 'I64', 'V', 'I'], romans
cads = [c['cadence'] for c in a['chords']]
assert cads == [None, None, 'HC', None, None, None, None, 'PAC'], cads
quals = [c['quality'] for c in a['chords']]
assert quals == ['major', 'minor', 'major', 'major', 'major', 'major', 'major', 'major'], quals
invs = [c['inversion'] for c in a['chords']]
assert invs == ['', '6', '', '6', '', '64', '', ''], invs
assert a['parallels'] == [], a['parallels']
print('linden-choir oracle: visible analysis self-check passed')
PY

echo "linden-choir oracle complete -> /app/analyze.py /app/analysis.json"
ls -l /app/analyze.py /app/analysis.json