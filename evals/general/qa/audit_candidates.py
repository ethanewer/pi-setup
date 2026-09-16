#!/usr/bin/env python3
"""Run existing contamination gates on a frozen copy of selected candidates."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from author_task import fingerprint, validate
import audit_independence_stream as audit
import check_task_similarity as similarity


def scoped_blocks(data, wanted):
    """Retain precisely the reference blocks that can match candidate content."""
    for size in audit.BLOCK_SIZES:
        for offset in range(0, len(data) - size + 1, max(1, size // 4)):
            block = data[offset:offset + size]
            digest = hashlib.blake2b(block, digest_size=8).digest()
            if digest in wanted:
                yield size, digest, audit.boilerplate_block(block), block


def scope_indexes(stage):
    # Keeping unrelated reference signatures consumes gigabytes and cannot affect
    # any candidate match. Thresholds, boilerplate decisions and reference-file
    # frequencies for matching signatures remain exactly those of the full audit.
    wanted_blocks = set()
    wanted_ngrams = set()
    original_ngrams = audit.word_ngrams
    for _, data in audit.iter_payloads(stage):
        for size in audit.BLOCK_SIZES:
            for offset in range(0, len(data) - size + 1, max(1, size // 4)):
                wanted_blocks.add(hashlib.blake2b(data[offset:offset + size], digest_size=8).digest())
        if len(data) <= audit.MAX_TEXT_NGRAM_BYTES:
            words = audit.normalize_text(data)
            if words is not None and audit.alpha_ratio(words) >= audit.MIN_ALPHA_WORD_RATIO:
                wanted_ngrams.update(original_ngrams(words))
    audit.block_digests = lambda data: scoped_blocks(data, wanted_blocks)
    audit.word_ngrams = lambda words, n=audit.NGRAM_N: (
        gram for gram in original_ngrams(words, n) if gram in wanted_ngrams)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, action='append', required=True)
    parser.add_argument('--suite-root', type=Path, action='append', help='one root for all candidates, or one per candidate in the same order')
    parser.add_argument('--reference-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    roots = args.suite_root or [ROOT]
    if len(roots) == 1:
        roots = roots * len(args.candidate)
    if len(roots) != len(args.candidate):
        parser.error('provide one suite root or one per candidate')
    args.output.mkdir(parents=True, exist_ok=False)
    result = subprocess.run([sys.executable, str(ROOT / 'tools/freeze_reference.py'),
                             '--verify', '--reference-root', str(args.reference_root)])
    if result.returncode:
        return result.returncode
    with tempfile.TemporaryDirectory(prefix='candidate-contamination-') as directory:
        stage = Path(directory)
        (stage / 'specs').mkdir()
        (stage / 'private-audit').mkdir()
        receipts = {}
        sources = []
        for path, suite_root in zip(args.candidate, roots):
            candidate = validate(json.loads(path.read_text()))
            name = candidate['task_id']
            task = suite_root / 'tasks' / name
            if not task.is_dir() or task.is_symlink():
                raise ValueError(f'{name}: missing or symlinked task')
            digest = fingerprint(task, candidate)
            shutil.copytree(task, stage / 'tasks' / name)
            if fingerprint(stage / 'tasks' / name, candidate) != digest:
                raise ValueError(f'{name}: changed during snapshot')
            receipts[name] = digest
            repo = candidate['source'].get('repository')
            if repo:
                repo = repo.removeprefix('https://').removeprefix('http://').removesuffix('.git').rstrip('/').lower()
                sources.append({'repository': repo, 'url': 'https://' + repo})
        shutil.copy2(ROOT / 'specs/frozen_reference.json', stage / 'specs/frozen_reference.json')
        (stage / 'specs/provenance.json').write_text(json.dumps({'external_sources': sources}))
        (args.output / 'fingerprints.json').write_text(json.dumps(receipts, indent=2) + '\n')
        audit.ROOT = stage
        similarity.ROOT = stage
        scope_indexes(stage)
        # Reference access occurs only here in QA, after authoring is finished.
        sys.argv = ['audit_independence_stream.py', '--reference-root', str(args.reference_root / 'original-tasks'),
                    '--reference-provenance', str(ROOT / 'specs/tb21_source_repositories.json')]
        audit_rc = audit.main()
        similarity_rc = similarity.triage(args.reference_root / 'original-tasks', args.output / 'blind-review-input.json')
        for name in ('independence_report.json', 'similarity_report.json'):
            shutil.copy2(stage / 'specs' / name, args.output / name)
        shutil.copy2(stage / 'private-audit/similarity_mapping.json', args.output / 'similarity_mapping.json')
        report = json.loads((args.output / 'similarity_report.json').read_text())
        summary = {'byte_audit_exit': audit_rc, 'similarity_exit': similarity_rc,
                   'flagged_pairs': len(report['flagged']),
                   'status': 'needs-review' if audit_rc or report['flagged'] else 'clear'}
        (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary))
        return 1 if audit_rc or similarity_rc or report['flagged'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
