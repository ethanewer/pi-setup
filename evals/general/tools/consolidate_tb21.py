#!/usr/bin/env python3
"""Consolidate the atomic competency inventory for the general-v2 benchmark.

Reads every batch_*.json competency file plus the frozen manifest, merges
near-duplicate/synonymous competency names into a single canonical competency,
derives per-competency opaque ids and metadata, and writes:
  - specs/tb21_competencies.json       (neutral render; no reference task names)
  - private-audit/competency_map.json  (private; may name reference tasks)
  - private-audit/competency_summary.md (private stats)
  - tools/competency_candidates.json   (private audit: raw name -> canonical)

Run from repo root:  python3 tools/consolidate_tb21.py
"""

import glob
import hashlib
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BATCH_DIR = os.path.join(ROOT, 'private-audit', 'competency_analysis')
SPECS_DIR = os.path.join(ROOT, 'specs')
PRIV_DIR = os.path.join(ROOT, 'private-audit')
MANIFEST_PATH = os.path.join(PRIV_DIR, 'frozen_manifest.json')
OUT_SPECS = os.path.join(SPECS_DIR, 'tb21_competencies.json')
OUT_MAP = os.path.join(PRIV_DIR, 'competency_map.json')
OUT_SUMMARY = os.path.join(PRIV_DIR, 'competency_summary.md')
OUT_CANDIDATES = os.path.join(ROOT, 'tools', 'competency_candidates.json')

RISK = {'low': 0, 'medium': 1, 'high': 2}
RISK_R = ['low', 'medium', 'high']
DIFF = {'easy': 0, 'medium': 1, 'hard': 2}
DIFF_R = ['easy', 'medium', 'hard']


# ---------------------------------------------------------------------------
# Cross-task synonym merges: (source-fragment, canonical neutral name).
# A source competency whose lowercased name CONTAINS (or equals) a fragment is
# assigned the canonical name.  Names are abstract and neutral.
# ---------------------------------------------------------------------------
SUBSTITUTIONS = [
    # certificate / TLS key material
    ("generate an rsa private key with a fixed modulus size and restrict permissions",
     "generate an RSA private key with restrictive permissions"),
    ("generate an rsa private key with restrictive permissions",
     "generate an RSA private key with restrictive permissions"),
    ("generate a self-signed certificate and matching private key for the domain",
     "create a self-signed X.509 certificate with the required subject and validity"),
    ("issue a self-signed x.509 certificate with chosen subject and validity",
     "create a self-signed X.509 certificate with the required subject and validity"),
    ("create a self-signed x.509 certificate with required subject and validity",
     "create a self-signed X.509 certificate with the required subject and validity"),
    ("bundle key and certificate into a single pem and report certificate facts",
     "bundle a private key and certificate into a single PEM container"),
    ("bundle private key and certificate into a pem container",
     "bundle a private key and certificate into a single PEM container"),
    ("write a python script that loads and validates the generated certificate",
     "write a program that loads and inspects a certificate and reports its attributes"),
    ("report certificate attributes via inspection",
     "write a program that loads and inspects a certificate and reports its attributes"),
    ("report certificate facts via inspection",
     "write a program that loads and inspects a certificate and reports its attributes"),

    # protected-archive entry
    ("crack a password-protected archive",
     "recover an archive password via wordlist or brute-force attack"),
    ("recover the archive password with a wordlist or brute-force attack",
     "recover an archive password via wordlist or brute-force attack"),
    ("unpack a password-protected archive",
     "extract the protected file/payload from an archive and persist its content"),
    ("extract the payload file and persist its content to a deliverable file",
     "extract the protected file/payload from an archive and persist its content"),
    ("extract and read the protected file from the archive",
     "extract the protected file/payload from an archive and persist its content"),

    # typed CSV output
    ("emit a well-formed csv report with a fixed header and exact row set",
     "write a typed CSV report with a fixed header and an exact required row set"),
    ("write a typed csv with an exact column schema",
     "write a typed CSV report with a fixed header and an exact required row set"),
    ("write records to a typed csv and a summary report",
     "write a typed CSV report with a fixed header and an exact required row set"),
    ("export the cleaned table to a csv with a header and stable order",
     "write a typed CSV report with a fixed header and an exact required row set"),

    # generic structured / JSON result serialization
    ("emit well-formed json documents with a required schema",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("write a spec-conforming nested json report with consistent counts",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("emit a schema-conforming, self-consistent json report from a runnable script",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("write aggregate statistics to a structured result file",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("write the fitted parameters to a json artifact",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("persist the spectral summary to a structured result file",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("write query-answer pairs to a written result file",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("record per-trial metrics to a self-reported json result",
     "write a schema-conforming structured (JSON) result to a required file path"),

    # write exact result value to a required file
    ("execute the algorithm and derive its final printed value",
     "execute a recovered algorithm and write the exact result value to a required file"),
    ("write a result to a fixed path with exact content",
     "write the exact result value/content to a required file"),
    ("execute the algorithm and emit the exact result value",
     "execute a recovered algorithm and write the exact result value to a required file"),

    # evaluation harness build/install
    ("build and system-install an evaluation harness from source",
     "build and install an evaluation harness from its source tree"),
    ("build and install a python harness package from its source tree",
     "build and install an evaluation harness from its source tree"),

    # LLM benchmark task / prompt template
    ("register a multiple-choice benchmark task",
     "register an automatically-scored multiple-choice evaluation task"),
    ("author a multiple-choice evaluation task config for an llm harness",
     "register an automatically-scored multiple-choice evaluation task"),
    ("render the mandated prompt exactly",
     "render each sample's prompt to the exact mandated template"),
    ("construct a fixed literal few-shot-free prompt template",
     "render each sample's prompt to the exact mandated template"),
    ("produce expected per-label accuracies",
     "align a benchmark's label/choice mapping so scores land in expected tolerances"),
    ("evaluate a benchmark and hit a tight per-model accuracy band",
     "align a benchmark's label/choice mapping so scores land in expected tolerances"),

    # dataset assembly (jsonl)
    ("extract and reshape a tabular multilingual product dataset in pandas",
     "assemble a filtered line-delimited JSON dataset from a versioned source"),
    ("assemble a filtered jsonl dataset from a versioned source",
     "assemble a filtered line-delimited JSON dataset from a versioned source"),

    # Nginx / web server
    ("install and start an nginx server serving a document root on a custom port",
     "install and run a web server on a custom port serving a document root"),
    ("author an nginx server block with a custom log format and log-file directives",
     "author a web-server block with a custom log format and log-file directives"),
    ("configure an nginx request rate-limit zone and apply it",
     "configure a web-server request rate-limit zone and apply it"),
    ("configure a custom http error page and validate/reload the server",
     "configure a custom HTTP error page and reload the server"),
    ("install, configure, and validate an nginx web server on a custom listener",
     "install and validate a syntax-valid web server on a custom port"),
    ("define and apply a request rate-limit policy and detail logging",
     "define and apply a web-server rate-limit policy and detail logging"),
    ("serve a custom error response for failed lookups",
     "serve a custom HTTP error response for a failed request"),

    # PDF form field enumeration / document-value assembly
    ("interactive form fields in a pdf",
     "enumerate the interactive form fields in a PDF"),
    ("fillable fields in a pdf form programmatically",
     "enumerate the interactive form fields in a PDF"),
    ("match document values to form fields via text-retrieval and record statistics",
     "match document values to form fields via a text-retrieval/similarity method"),
    ("match document values to form fields with a retrieval/similarity approach",
     "match document values to form fields via a text-retrieval/similarity method"),
    ("run a python entrypoint end-to-end and regenerate the report on demand",
     "provide a runnable entrypoint that regenerates a structured report on demand"),
    ("emit a reproducible report from a runnable script",
     "provide a runnable entrypoint that regenerates a structured report on demand"),
    ("run a python entrypoint that regenerates the report on demand",
     "provide a runnable entrypoint that regenerates a structured report on demand"),
    ("write query-answer pairs to a structured result file",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("serialize decoded records to a structured output",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("write a numeric result to a specified answer file",
     "write the exact result value/content to a required file"),
    ("produce a map output file per maze",
     "write one structured result file per input instance"),
    ("fetch and parse a local web page",
     "fetch and parse an HTTP page from a served endpoint"),
    ("fetch and validate an http page from a local server",
     "fetch and parse an HTTP page from a served endpoint"),
    ("extract targeted entity values from plain-text source documents",
     "extract targeted entity values from plain-text source documents"),
    ("extract candidate values from text documents via pattern matching",
     "extract targeted entity values from plain-text source documents"),
    ("write a spec-conforming nested json report with consistent counts",
     "write a schema-conforming structured (JSON) result to a required file path"),
    ("emit a schema-conforming, self-consistent json report from a runnable script",
     "write a schema-conforming structured (JSON) result to a required file path"),

    # byte / binary reading
    ("read words at virtual-address-stride addresses in little-endian order",
     "read words at fixed virtual-address-stride locations in little endian order"),

    # COBOL / legacy fixed records
    ("decode a fixed-column record layout from flat data files",
     "decode a fixed-column record layout from flat data files"),
    ("emit byte-identical flat output records",
     "reproduce byte-identical fixed-width output records"),
    ("reimplement fixed-width binary-decimal record parsing and formatting in python",
     "reimplement fixed-width binary-decimal record parsing and formatting in another language"),
    ("model a multi-file transactional ledger update in python",
     "model a multi-file transactional ledger update in another language"),

    # base64 / deobfuscation
    ("decode base64-encoded file content into an output file",
     "decode base64-encoded file content into a reconstructed output file"),
    ("decode through stacked base64 and gzip/bzip2 compression layers",
     "decode through stacked base64 and gzip/bzip2 compression layers"),
]


# ---------------------------------------------------------------------------
def normalize(name: str) -> str:
    n = re.sub(r'\s+', ' ', name).strip().rstrip('.')
    return n[:1].upper() + n[1:] if n else n


def canonicalize(raw_name: str) -> str:
    low = re.sub(r'\s+', ' ', raw_name.strip().lower())
    for frag, canonical in SUBSTITUTIONS:
        if frag in low or low == frag:
            return canonical
    return normalize(raw_name)


def cid(name: str) -> str:
    h = hashlib.sha256((name + '|general-v2').encode()).hexdigest()
    return 'C-' + h[:8]


def split_artifacts(a: str):
    if not a:
        return []
    parts = re.split(r'[,;]| and | plus | }', a)
    return [p.strip().rstrip('.') for p in parts if p.strip()]


# ---------------------------------------------------------------------------
# Neutralization table for the PUBLIC spec render. Distinctive product/vendor
# names, tool names, paths and numeric constants identifying a reference task
# are replaced with neutral phrasing before writing specs/tb21_competencies.json.
# The private map keeps the full descriptions.
# ---------------------------------------------------------------------------
SCRUB = [
    (r'\bqemu\b', 'the emulator'),
    (r'\bopenresty\b', 'the web server'),
    (r'\bnginx\b', 'the web server'),
    (r'\bflask\b', 'the web framework'),
    (r'\bfasttext\b', 'the text-classification toolkit'),
    (r'\blean\b', 'the proof toolchain'),
    (r'\bcobol\b', 'the legacy record-format program'),
    (r'\bsudoku\b', 'number-placement puzzle'),
    (r'\bfeal-?\b', 'the test block cipher'),
    (r'\bgpt-?2\b', 'the transformer language model'),
    (r'/app', 'the application directory'),
    (r'\bgit\b', 'the version-control system'),
    (r'solution\.txt', 'the required output file'),
    (r'attack\.py', 'the required attack script'),
    (r'output\.toml', 'the required structured report'),
    (r'primers\.fasta', 'the required FASTA file'),
    (r'\bvim\b', 'the editor'),
]


def scrub_text(text: str) -> str:
    if not text:
        return text
    out = text
    for pat, rep in SCRUB:
        out = re.sub(pat, rep, out, flags=re.IGNORECASE)
    return out


def write_summary(competencies, manifest, covered_tasks, map_out):
    n = len(competencies)
    by_risk = {k: 0 for k in RISK}
    by_diff = {k: 0 for k in DIFF}
    two_task = 0
    env = {'emulation': 0, 'gpu': 0, 'heavy_install': 0, 'interactive': 0}
    for c in competencies:
        by_risk[c['risk']] += 1
        by_diff[c['min_required_difficulty']] += 1
        if c['second_task_required']:
            two_task += 1
        needs = map_out.get(c['id'], {}).get('environment_needs', {})
        for k in env:
            if any(v.get(k) for v in needs.values()):
                env[k] += 1

    # heaviest = highest difficulty floor, then single/fewest reference tasks
    def heaviness(c):
        info = map_out[c['id']]
        return (DIFF[c['min_required_difficulty']], -len(info['reference_tasks']), c['name'])
    rare = sorted(competencies, key=heaviness, reverse=True)[:30]
    rare_lines = ['- **' + c['name'] + '** (' + c['id'] + ') — ' +
                  c['min_required_difficulty'] + ', ' + c['risk'] + ', evidence: ' +
                  ', '.join(map_out[c['id']]['reference_tasks']) for c in rare]

    lines = []
    lines.append('# Competency Consolidation Summary — general-v2\n')
    lines.append(f'- frozen commit: `{manifest.get("commit","")}` (frozen {manifest.get("frozen_at","")})')
    lines.append(f'- reference tasks covered: {len(covered_tasks)}')
    lines.append(f'- total consolidated competencies: {n}\n')
    lines.append('## Counts by risk')
    for k in RISK:
        lines.append(f'- **{k}**: {by_risk[k]}')
    lines.append('\n## Counts by minimum required difficulty (floor)')
    for k in DIFF:
        lines.append(f'- **{k}**: {by_diff[k]}')
    lines.append('\n## Competencies needing two reference tasks')
    lines.append(f'- {two_task}')
    lines.append('\n## Competencies needing a special environment')
    for k, lab in [('emulation','emulation'), ('gpu','GPU'), ('heavy_install','heavy installs'), ('interactive','interactive TTY')]:
        lines.append(f'- **{lab}**: {env[k]}')
    lines.append('\n## Heaviest / rarest competencies (with reference tasks)')
    lines.extend(rare_lines)
    lines.append('')
    with open(OUT_SUMMARY, 'w') as fh:
        fh.write('\n'.join(lines) + '\n')


def main():
    os.makedirs(SPECS_DIR, exist_ok=True)
    os.makedirs(PRIV_DIR, exist_ok=True)

    batches = {}
    for f in sorted(glob.glob(os.path.join(BATCH_DIR, 'batch-*.json'))):
        batches.update(json.load(open(f)))

    manifest = json.load(open(MANIFEST_PATH))

    def task_difficulty(task):
        m = manifest.get('tasks', {}).get(task)
        if m:
            d = m.get('metadata', {}).get('difficulty')
            if d in DIFF:
                return d
        d = batches.get(task, {}).get('difficulty')
        return d if d in DIFF else 'medium'

    def task_env(task):
        return batches.get(task, {}).get('environment', {}) or {}

    # collect records
    records = []
    covered = set()
    for task, info in batches.items():
        comp = info.get('competencies') or []
        if not comp:
            continue
        diff = task_difficulty(task)
        env = task_env(task)
        for c in comp:
            if not c.get('name'):
                continue
            records.append({
                'task': task,
                'name': normalize(c['name']),
                'canon': canonicalize(c['name']),
                'definition': c.get('definition', ''),
                'failure': c.get('failure_mode', ''),
                'artifact': c.get('required_artifact', ''),
                'risk': c.get('risk', 'medium') if (c.get('risk') or 'medium') in RISK else 'medium',
                'difficulty': diff,
                'env': env,
            })
            covered.add(task)

    # cluster
    clusters = {}
    order = []
    for r in records:
        key = r['canon']
        if key not in clusters:
            clusters[key] = {'canon': key, 'members': []}
            order.append(key)
        clusters[key]['members'].append(r)

    # build competencies + map
    competencies = []
    map_out = {}
    for key in order:
        mem = clusters[key]['members']
        rep = max(mem, key=lambda m: (RISK.get(m['risk'], 1), len(m['definition'] or '')))
        risk = max(RISK[m['risk']] for m in mem)
        ref_tasks = sorted({m['task'] for m in mem})
        min_diff = max(DIFF.get(m['difficulty'], 1) for m in mem)

        artifacts = []
        seen_a = set()
        for m in mem:
            for a in split_artifacts(m['artifact']):
                ka = a.lower()
                if ka not in seen_a and a:
                    seen_a.add(ka)
                    artifacts.append(a)

        comp = {
            'id': cid(key),
            'name': key,
            'definition': scrub_text(rep['definition']),
            'failure_mode': scrub_text(rep['failure']),
            'required_artifacts': [scrub_text(a) for a in artifacts],
            'risk': RISK_R[risk],
            'min_required_difficulty': DIFF_R[min_diff],
            'second_task_required': risk >= RISK['high'] or len(ref_tasks) == 1,
            'variants': sorted(m['name'] for m in mem),
        }
        competencies.append(comp)
        map_out[comp['id']] = {
            'canonical_name': key,
            'reference_tasks': ref_tasks,
            'reference_difficulties': {t: task_difficulty(t) for t in ref_tasks},
            'reference_evidence': {m['task']: m['definition'] for m in mem},
            'environment_needs': {t: task_env(t) for t in ref_tasks},
        }

    competencies.sort(key=lambda c: (DIFF[c['min_required_difficulty']], c['name']))

    spec = {
        'version': 1,
        'description': 'Abstract atomic competency inventory required by the frozen reference suite. Neutral descriptions only.',
        'frozen_commit': manifest.get('commit', ''),
        'frozen_at': manifest.get('frozen_at', ''),
        'competency_count': len(competencies),
        'competencies': competencies,
    }
    with open(OUT_SPECS, 'w') as fh:
        json.dump(spec, fh, indent=2)
        fh.write('\n')
    with open(OUT_MAP, 'w') as fh:
        json.dump(map_out, fh, indent=2)
        fh.write('\n')
    with open(OUT_CANDIDATES, 'w') as fh:
        json.dump({r['name']: r['canon'] for r in records}, fh, indent=2)
        fh.write('\n')

    write_summary(competencies, manifest, covered, map_out)

    print('records:', len(records), 'covered tasks:', len(covered), 'competencies:', len(competencies))
    print('distinct source names:', len({r['name'] for r in records}))


if __name__ == '__main__':
    main()