#!/usr/bin/env python3
"""Suite-level completion report (TODO.md 4.3 + section 7 evidence).

Aggregates every gate artifact into one archived report:
  private-audit/reports/suite_report.json
Prints the required suite-level block:
  v2_easy_count, v2_medium_count, v2_hard_count,
  all_required_competencies_have_real_verifier_evidence,
  no_task_has_unexplained_infrastructure_failures
Exits nonzero unless every TODO completion-gate value is satisfied.
"""
import datetime, json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(rel):
    p = ROOT / rel
    return json.loads(p.read_text()) if p.exists() else None


def main() -> int:
    diff = load('specs/difficulty.json')
    cov = load('specs/coverage.json')
    inv = load('specs/tb21_competencies.json')
    oracle = load('specs/oracle_report.json')
    indep = load('specs/independence_report.json')
    similarity = load('specs/similarity_report.json')

    problems = []
    counts = diff['suite_counts'] if diff else {}

    # difficulty buckets
    easy_ok = counts.get('easy', 0) >= 1
    med_ok = counts.get('medium', 0) >= 1
    hard_ok = counts.get('hard', 0) >= 1

    # coverage evidence
    evidence_ok = True
    infeasible_ids = set()
    infeas_dir = ROOT / 'private-audit/infeasible'
    if infeas_dir.exists():
        for f in infeas_dir.glob('*.json'):
            try:
                infeasible_ids |= set(json.loads(f.read_text()).get('competencies', []))
            except Exception:
                pass
    second_task_gap = 0
    if cov and inv:
        comps = {c['id']: c for c in inv['competencies']}
        for cid, c in comps.items():
            if cid in infeasible_ids:
                continue  # documented environmentally-infeasible; waived
            cells = cov['matrix'].get(cid, [])
            real = [x for x in cells if x.get('evidence', '').strip()
                    and x.get('hidden_cases')
                    and x.get('verifier_kind') in
                    ('executes-deliverable', 'answer-with-hidden-cases')]
            if not real:
                evidence_ok = False
                problems.append(f'no real verifier evidence for {cid}')
            if c.get('second_task_required') and \
                    len({x['task_id'] for x in real}) < 2:
                second_task_gap += 1
    else:
        evidence_ok = False
        problems.append('coverage or inventory missing')

    # oracle results: infra health
    infra_ok = True
    if oracle:
        for task, r in oracle['tasks'].items():
            if r.get('errored') or r.get('reward') != 1.0:
                infra_ok = False
                problems.append(f"oracle failure: {task} "
                                f"(reward={r.get('reward')}, "
                                f"errored={r.get('errored')})")
    else:
        infra_ok = False
        problems.append('oracle report missing')

    # independence
    indep_ok = bool(indep) and not (
        indep['exact_matches'] or indep['block_matches']
        or indep.get('ngram_matches') or indep['canary_matches']
        or indep['source_repository_matches'])
    if not indep_ok:
        problems.append('independence audit not clean')

    # similarity: no unresolved flagged pairs
    sim_ok = similarity is not None
    flagged = similarity.get('flagged') if similarity else []
    if flagged:
        # Triage flags are acceptable once two-person blind review has cleared
        # every flagged pair with no direct-recipe verdict.
        verdicts = load('reports/blind_review_verdicts.json') or {}
        mapping = load('private-audit/similarity_mapping.json') or {}
        reviews = verdicts.get('reviews') or verdicts.get('verdicts') or []
        verdict_by_pair = {}
        for r in reviews:
            verdict_by_pair.setdefault(r.get('pair_id'), []).append(r.get('verdict'))
        flag_set = {(f.get('v2_task'), f.get('reference_task')) for f in flagged}
        covered = set()
        for pid, m in mapping.items():
            key = (m.get('v2_task'), m.get('reference_task'))
            if key in flag_set and pid in verdict_by_pair:
                covered.add(key)
        all_covered = bool(flag_set) and covered == flag_set
        no_recipe = all(v != 'direct-recipe'
                        for vs in verdict_by_pair.values() for v in vs)
        if not (all_covered and no_recipe):
            sim_ok = False
            problems.append(f'{len(flag_set) - len(covered)} flagged similarity '
                            'pairs lack clearing blind-review verdicts')
    report_sim_flagged = len(flagged)

    report = {
        'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'v2_easy_count': counts.get('easy', 0),
        'v2_medium_count': counts.get('medium', 0),
        'v2_hard_count': counts.get('hard', 0),
        'all_required_competencies_have_real_verifier_evidence': evidence_ok,
        'no_task_has_unexplained_infrastructure_failures': infra_ok,
        'independence_clean': indep_ok,
        'similarity_triage_clean': sim_ok,
        'similarity_flagged_pairs': report_sim_flagged,
        'infeasible_competencies_waived': len(infeasible_ids),
        'second_task_shortfall': second_task_gap,
        'task_count': len(diff['tasks']) if diff else 0,
        'competency_count': len(inv['competencies']) if inv else 0,
    }
    out = ROOT / 'private-audit/reports'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'suite_report.json').write_text(json.dumps(report, indent=2) + '\n')

    print(f"v2_easy_count = {report['v2_easy_count']}")
    print(f"v2_medium_count = {report['v2_medium_count']}")
    print(f"v2_hard_count = {report['v2_hard_count']}")
    print('all_required_competencies_have_real_verifier_evidence = '
          + str(evidence_ok).lower())
    print('no_task_has_unexplained_infrastructure_failures = '
          + str(infra_ok).lower())
    for p in problems:
        print('ERROR', p)
    ok = easy_ok and med_ok and hard_ok and evidence_ok and infra_ok \
        and indep_ok and sim_ok
    print('SUITE', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
