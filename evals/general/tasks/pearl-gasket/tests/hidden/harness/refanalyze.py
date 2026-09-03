#!/usr/bin/env python3
"""Independent reference implementation of the pearl-gasket analysis
contract (documented in instruction.md). Recomputed from the fixture score at
verification time; no fixed answer files. Pure stdlib, deterministic.

The reference intentionally follows the documented ruleset only: pitch/note
grammar, key grammar, the major/minor diatonic triad pools, subset matching,
bass-determined inversion, phrase-final cadence rules, and rank-pair parallel
detection.
"""
import json
import re

_NOTE_RE = re.compile(r'^([A-G])([#b]?)([0-9])$')
_KEY_RE = re.compile(r'^([A-G])([#b]?)(maj|min)$')
_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(note):
    m = _NOTE_RE.match(note)
    if not m:
        raise ValueError('malformed note %r' % note)
    pc = (_PC[m.group(1)] + (1 if m.group(2) == '#' else -1 if m.group(2) == 'b' else 0)) % 12
    return (int(m.group(3)) + 1) * 12 + pc


def _key_info(key):
    m = _KEY_RE.match(key)
    if not m:
        raise ValueError('malformed key %r' % key)
    tonic = (_PC[m.group(1)] + (1 if m.group(2) == '#' else -1 if m.group(2) == 'b' else 0)) % 12
    return tonic, m.group(3)


def _triad_pool(tonic, mode):
    """Return list of (pcs, roman, quality, root, third, fifth) diatonics."""
    if mode == 'maj':
        scale = [(tonic + iv) % 12 for iv in (0, 2, 4, 5, 7, 9, 11)]
        table = (('I', 'major'), ('ii', 'minor'), ('iii', 'minor'),
                 ('IV', 'major'), ('V', 'major'), ('vi', 'minor'),
                 ('vii\u00b0', 'diminished'))
        out = []
        for d, (roman, quality) in enumerate(table):
            root = scale[d]
            third = (root + (4 if quality == 'major' else 3)) % 12
            fifth = (root + (7 if quality != 'diminished' else 6)) % 12
            out.append(({scale[d], scale[(d + 2) % 7], scale[(d + 4) % 7]},
                        roman, quality, root, third, fifth))
        return out
    # minor keys: natural-minor degrees 1..7 plus raised-7th V and vii
    nat = [(tonic + iv) % 12 for iv in (0, 2, 3, 5, 7, 8, 10)]
    raised = (tonic + 11) % 12
    entries = (
        ({nat[0], nat[2], nat[4]}, 'i', 'minor', nat[0]),
        ({nat[1], nat[3], nat[5]}, 'ii\u00b0', 'diminished', nat[1]),
        ({nat[2], nat[4], nat[6]}, 'III', 'major', nat[2]),
        ({nat[3], nat[5], nat[0]}, 'iv', 'minor', nat[3]),
        ({nat[4], raised, nat[1]}, 'V', 'major', nat[4]),
        ({nat[4], nat[6], nat[1]}, 'v', 'minor', nat[4]),
        ({nat[5], nat[0], nat[2]}, 'VI', 'major', nat[5]),
        ({nat[6], nat[1], nat[3]}, 'VII', 'major', nat[6]),
        ({raised, nat[1], nat[3]}, 'vii\u00b0', 'diminished', raised),
    )
    out = []
    for pcs, roman, quality, root in entries:
        third = (root + (4 if quality == 'major' else 3)) % 12
        fifth = (root + (7 if quality != 'diminished' else 6)) % 12
        out.append((pcs, roman, quality, root, third, fifth))
    return out


def analyze(score):
    if not isinstance(score, dict) or 'key' not in score or 'chords' not in score:
        raise ValueError('score must be an object with "key" and "chords"')
    tonic, mode = _key_info(score['key'])
    pool = _triad_pool(tonic, mode)
    chords = score['chords']
    if not isinstance(chords, list):
        raise ValueError('"chords" must be a list')

    entries = []
    for ch in chords:
        if (not isinstance(ch, dict) or 'beat' not in ch
                or 'duration' not in ch or 'notes' not in ch):
            raise ValueError('chord missing beat/duration/notes')
        notes = sorted(ch['notes'], key=midi)
        distinct = frozenset(midi(n) % 12 for n in ch['notes'])
        bass = midi(notes[0]) % 12
        hits = [t for t in pool if t[0] <= distinct]
        if not hits:
            raise ValueError('chord at beat %s matches no diatonic triad' % ch['beat'])
        chosen = None
        bass_root = [t for t in hits if t[3] == bass]
        if len(bass_root) == 1:
            chosen = bass_root[0]
        else:
            keyed = bass_root if bass_root else hits
            chosen = min(keyed, key=lambda t: (t[3], pool.index(t)))
        roman, quality, root, third, fifth = chosen[1], chosen[2], chosen[3], chosen[4], chosen[5]
        if bass == root:
            inv = ''
        elif bass == third:
            inv = '6'
        elif bass == fifth:
            inv = '64'
        else:
            inv = ''
        entries.append({'beat': ch['beat'],
                        'roman': roman + ('6' if inv == '6' else '64' if inv == '64' else ''),
                        'quality': quality, 'inversion': inv, 'cadence': None})

    last = len(chords) - 1
    dom = ('V', 'V6', 'vii\u00b0', 'vii\u00b06')
    ton = ('I', 'I6', 'i', 'i6')
    for i in range(1, len(chords)):
        if i != last and not (chords[i]['duration'] >= 2):
            continue
        soprano = midi(sorted(chords[i]['notes'], key=midi)[-1]) % 12
        prev, cur = entries[i - 1]['roman'], entries[i]['roman']
        cadence = None
        if prev in dom and cur in ton:
            if prev == 'V' and cur in ('I', 'i') and soprano == tonic:
                cadence = 'PAC'
            else:
                cadence = 'IAC'
        elif cur == 'V':
            cadence = 'HC'
        elif prev in ('IV', 'iv') and cur in ('I', 'i'):
            cadence = 'PLAGAL'
        entries[i]['cadence'] = cadence

    parallels = []
    for i in range(len(chords) - 1):
        a = sorted(chords[i]['notes'], key=midi)
        b = sorted(chords[i + 1]['notes'], key=midi)
        for j in range(min(len(a), len(b))):
            for k in range(j + 1, min(len(a), len(b))):
                da = (midi(a[k]) - midi(a[j])) % 12
                db = (midi(b[k]) - midi(b[j])) % 12
                if da == db == 7:
                    parallels.append({'beats': [chords[i]['beat'], chords[i + 1]['beat']],
                                      'interval': 'P5'})
                elif (da == db == 0 and midi(a[k]) != midi(a[j])
                      and midi(b[k]) != midi(b[j])):
                    parallels.append({'beats': [chords[i]['beat'], chords[i + 1]['beat']],
                                      'interval': 'P8'})

    return {'chords': entries, 'parallels': parallels}


def main(argv):
    import sys
    if len(argv) != 2:
        print('usage: refanalyze.py <score.json>', file=sys.stderr)
        return 2
    with open(argv[1], 'r', encoding='utf-8') as fh:
        score = json.load(fh)
    print(json.dumps(analyze(score), indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv))