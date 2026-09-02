#!/usr/bin/env python3
"""Task-similarity triage + blind two-reviewer direct-mapping gate.

Modes:
  --mode triage (default)
      Compare every v2 task's instruction.md and solution/test text against
      every reference task's instruction text using word-n-gram Jaccard and
      shared long character n-grams.  Embedding similarity is deliberately not
      required; n-grams are the triage signal.  Writes:
        specs/similarity_report.json        full scored pairs above threshold
        <blind-review-input>.json           flagged pairs with opaque IDs and
                                            no source-task mapping
      The private pair->reference mapping is written to
        private-audit/similarity_mapping.json (never into the review file).

  --mode review --review-file PATH
      Every flagged pair must have verdicts from two independent reviewers,
      each verdict in {independent, shared-approach, direct-recipe}.  Fails if
      any pair lacks two verdicts or any reviewer says direct-recipe.

Fails closed when the reference root is missing.
"""
import argparse, hashlib, json, random, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORD_N = 6
CHAR_N = 24
JACCARD_FLAG = 0.08
LONGGRAM_FLAG = 3


def words(text: str):
    return re.findall(r'[a-z0-9_$./+-]+', text.lower())


def word_ngrams(ws, n=WORD_N):
    return {' '.join(ws[i:i + n]) for i in range(len(ws) - n + 1)} if len(ws) >= n else set()


def char_ngrams(text: str, n=CHAR_N):
    t = re.sub(r'\s+', ' ', text.lower())
    return {t[i:i + n] for i in range(len(t) - n + 1)} if len(t) >= n else set()


def ref_instruction(task_dir: Path) -> str:
    parts = []
    p = task_dir / 'instruction.md'
    if p.exists():
        parts.append(p.read_text(errors='replace'))
    ty = task_dir / 'task.yaml'
    if ty.exists():
        text = ty.read_text(errors='replace')
        m = re.search(r'instruction:\s*\|-?\s*\n(.*?)(?=\nauthor_name|\ndifficulty:|\Z)',
                      text, re.S)
        if m:
            parts.append(m.group(1))
    return '\n'.join(parts)


def triage(ref_root: Path, review_input: Path) -> int:
    v2_tasks = sorted(p for p in (ROOT / 'tasks').iterdir() if p.is_dir())
    ref_tasks = sorted(p for p in ref_root.iterdir() if p.is_dir())
    if not ref_tasks:
        print(f'ERROR no reference tasks under {ref_root}')
        return 1

    print(f'indexing {len(ref_tasks)} reference tasks ...')
    ref_index = []
    for rt in ref_tasks:
        text = ref_instruction(rt)
        if not text.strip():
            continue
        ref_index.append((rt.name, word_ngrams(words(text)), char_ngrams(text)))

    flagged = []
    for d in v2_tasks:
        ip = d / 'instruction.md'
        if not ip.exists():
            continue
        text = ip.read_text(errors='replace')
        wg = word_ngrams(words(text))
        cg = char_ngrams(text)
        if not wg:
            continue
        for rname, rwg, rcg in ref_index:
            inter = len(wg & rwg)
            if inter == 0:
                continue
            jac = inter / len(wg | rwg)
            long_shared = len(cg & rcg)
            if jac >= JACCARD_FLAG or long_shared >= LONGGRAM_FLAG:
                flagged.append({
                    'v2_task': d.name,
                    'reference_task': rname,
                    'word_jaccard': round(jac, 4),
                    'shared_long_ngrams': long_shared,
                })

    flagged.sort(key=lambda x: (-x['word_jaccard'], -x['shared_long_ngrams']))
    (ROOT / 'specs/similarity_report.json').write_text(
        json.dumps({'threshold_word_jaccard': JACCARD_FLAG,
                    'threshold_long_ngrams': LONGGRAM_FLAG,
                    'flagged': flagged}, indent=2) + '\n')

    # blind review input: opaque pair IDs, shuffled, no mapping
    rng = random.Random(20260826)
    pairs = []
    mapping = {}
    for f in flagged:
        pid = hashlib.sha256(
            f"{f['v2_task']}|{f['reference_task']}".encode()).hexdigest()[:10]
        mapping[pid] = f
        v2_text = (ROOT / 'tasks' / f['v2_task'] / 'instruction.md').read_text(
            errors='replace')
        ref_text = ref_instruction(ref_root / f['reference_task'])
        pairs.append({
            'pair_id': pid,
            'document_a': v2_text,
            'document_b': ref_text,
            'question': ('If an agent had already solved document B, would it '
                         'have a direct recipe (same objective + same route + '
                         'same checks) for document A? Answer one of: '
                         'independent | shared-approach | direct-recipe'),
        })
    rng.shuffle(pairs)
    review_input.write_text(json.dumps({'pairs': pairs}, indent=2) + '\n')
    (ROOT / 'private-audit/similarity_mapping.json').write_text(
        json.dumps(mapping, indent=2) + '\n')

    print(f'v2_tasks={len(v2_tasks)} reference_tasks={len(ref_index)} '
          f'flagged_pairs={len(flagged)}')
    for f in flagged[:20]:
        print(f"FLAG {f['v2_task']} ~ {f['reference_task']} "
              f"jac={f['word_jaccard']} longgrams={f['shared_long_ngrams']}")
    return 0


def review(review_file: Path) -> int:
    report_path = ROOT / 'specs/similarity_report.json'
    if not report_path.exists():
        print('ERROR run --mode triage first')
        return 1
    report = json.loads(report_path.read_text())
    flagged = report['flagged']
    if not review_file.exists():
        print(f'ERROR review file missing: {review_file}')
        return 1
    reviews = json.loads(review_file.read_text())
    # reviews: {"<pair_id>": ["verdict1", "verdict2"]} from two blind reviewers
    verdicts_by_pair = {}
    for entry in reviews if isinstance(reviews, list) else reviews.get('reviews', []):
        verdicts_by_pair.setdefault(entry['pair_id'], []).append(
            (entry.get('reviewer'), entry.get('verdict')))
    problems = []
    valid = {'independent', 'shared-approach', 'direct-recipe'}
    needed = {hashlib.sha256(
        f"{f['v2_task']}|{f['reference_task']}".encode()).hexdigest()[:10]
        for f in flagged}
    for pid in sorted(needed):
        vs = verdicts_by_pair.get(pid, [])
        reviewers = {r for r, _ in vs}
        if len(vs) < 2 or len(reviewers) < 2:
            problems.append(f'pair {pid}: needs verdicts from two reviewers, '
                            f'has {len(vs)}')
            continue
        for r, v in vs:
            if v not in valid:
                problems.append(f'pair {pid}: reviewer {r} invalid verdict {v!r}')
            if v == 'direct-recipe':
                problems.append(f'pair {pid}: reviewer {r} says direct-recipe; '
                                'the v2 task must be rejected or rebuilt')
    print(f'flagged_pairs={len(needed)} reviewed_pairs={len(verdicts_by_pair)} '
          f'problems={len(problems)}')
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--mode', choices=('triage', 'review'), default='triage')
    ap.add_argument('--reference-root', type=Path, default=None)
    ap.add_argument('--blind-review-input', type=Path,
                    default=Path('/tmp/general-v2-similarity-review.json'))
    ap.add_argument('--review-file', type=Path, default=None)
    args = ap.parse_args()

    if args.mode == 'review':
        return review(args.review_file or args.blind_review_input.with_suffix('.verdicts.json'))

    ref_root = args.reference_root
    if ref_root is None:
        cfg = ROOT / 'specs/frozen_reference.json'
        if cfg.exists():
            ref_root = Path(json.loads(cfg.read_text())['reference_root'])
    if ref_root is None or not ref_root.exists():
        print(f'ERROR reference root missing: {ref_root}')
        return 1
    return triage(ref_root, args.blind_review_input)


if __name__ == '__main__':
    sys.exit(main())
