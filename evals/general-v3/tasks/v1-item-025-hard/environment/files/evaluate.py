#!/usr/bin/env python3
"""Evaluator for the item-025 document-pipeline task.

Run:  python3 /app/evaluate.py

Checks the CONSISTENCY of the routing (no leaked/duplicated/lost inputs, valid
report), not the classification itself. Prints a summary and exits non-zero if
anything is inconsistent.
"""
import json
import os
import sys

INBOX = '/app/inbox'
PROCESSED = '/app/processed'
REPORT = '/app/processed/report.json'

SOURCES = ['doc-01.pdf', 'doc-02.pdf', 'doc-03.png', 'doc-04.png',
           'doc-05.pdf', 'doc-06.pdf', 'doc-07.png', 'doc-08.bin']

errors = []


def main():
    if not os.path.isdir(INBOX):
        errors.append('inbox missing')
    else:
        leftover = [f for f in os.listdir(INBOX) if os.path.isfile(os.path.join(INBOX, f))]
        if leftover:
            errors.append('inbox not empty: %r' % leftover)

    if not os.path.isdir(PROCESSED):
        errors.append('processed dir missing')

    # every expected source appears exactly once across the three folders
    found = {}
    for folder in ('invoices', 'receipts', 'unknown'):
        d = os.path.join(PROCESSED, folder)
        if os.path.isdir(d):
            for name in os.listdir(d):
                found.setdefault(name, set()).add(folder)

    for s in SOURCES:
        locs = found.get(s)
        if not locs:
            errors.append('source %s not found in any processed folder' % s)
        elif len(locs) > 1:
            errors.append('source %s routed to multiple folders: %r' % (s, sorted(locs)))

    # unknown files must only be in 'unknown'
    for fn, folders in found.items():
        if 'unknown' in folders and len(folders) > 1:
            errors.append('file %s in unknown and elsewhere' % fn)

    # report.json must exist, parse, and exactly cover the 8 sources
    if not os.path.isfile(REPORT):
        errors.append('report.json missing')
    else:
        try:
            with open(REPORT) as f:
                data = json.load(f)
        except Exception as e:
            errors.append('report.json invalid: %r' % e)
            data = None
        if data is not None:
            recs = data.get('records') if isinstance(data, dict) else None
            if not isinstance(recs, list):
                errors.append('report.json has no records list')
            else:
                names = sorted(r.get('source') for r in recs)
                if names != sorted(SOURCES):
                    errors.append('report sources mismatch: %r' % names)
                for r in recs:
                    if r.get('destination') not in ('invoices', 'receipts', 'unknown'):
                        errors.append('bad destination in report for %s' % r.get('source'))
                    if r.get('method') not in ('pdf_text', 'ocr', 'unknown'):
                        errors.append('bad method in report for %s' % r.get('source'))

    if errors:
        print('INCONSISTENT')
        for e in errors:
            print('  -', e)
        sys.exit(1)
    print('CONSISTENT: all 8 inputs routed exactly once; report valid')


if __name__ == '__main__':
    main()