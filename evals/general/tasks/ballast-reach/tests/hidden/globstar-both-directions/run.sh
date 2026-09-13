#!/bin/bash
# Hidden case: the direct translate_pattern contract with GLOBSTAR patterns,
# all four rule-direction/candidate-direction combinations, plus negative
# controls proving the fix does not over-match names that are genuinely
# different (accentless spelling, different extension).
set -u
cd "$(dirname "$0")"
python3 - <<'PY'
import unicodedata
from setuptools.command.egg_info import translate_pattern

pcomposed = translate_pattern(unicodedata.normalize('NFC', '**/static/café*.css'))
pdecomposed = translate_pattern(unicodedata.normalize('NFD', '**/static/café*.css'))
cand_nfd = unicodedata.normalize('NFD', 'app/static/café-main.css')
cand_nfc = unicodedata.normalize('NFC', 'app/static/café-main.css')

assert pcomposed.match(cand_nfd), 'NFC rule x NFD candidate'
assert pcomposed.match(cand_nfc), 'NFC rule x NFC candidate'
assert pdecomposed.match(cand_nfc), 'NFD rule x NFC candidate'
assert pdecomposed.match(cand_nfd), 'NFD rule x NFD candidate'

# negative controls: normalization must not make distinct names collide
assert not pcomposed.match(unicodedata.normalize('NFD', 'app/static/cafe-main.css')), \
    'accentless name matched composed rule'
assert not pcomposed.match('app/static/café-main.js'), 'different extension matched'
assert not pdecomposed.match('app/static/café-main.txt'), \
    'different extension matched NFD rule'
print('case-ok')
PY