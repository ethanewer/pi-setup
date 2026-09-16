# Source receipt: pyyaml-config-overlay

## Selection and immutable identity

- Assignment source list: /Users/ethanewer/posttraining-2606/local/data/terminal_docs_v004/libraries_frameworks_github.csv, row 423 (YAML,https://github.com/yaml/pyyaml).
- Repository: https://github.com/yaml/pyyaml
- Retrieved with: git clone https://github.com/yaml/pyyaml.git
- Base commit: 34a9bf82357f4952d8f194a5a31f1c39743652d0
- Commit metadata: 2026-06-17T18:15:29-04:00, Dos in merge key (#937)
- Package snapshot: the task environment contains a git archive of that exact commit under environment/pyyaml/; .git history is not shipped.
- License: MIT, as stated in README.md and retained verbatim in environment/pyyaml/LICENSE.

## Material actually inspected

- README.md: safe loading guidance, testing commands, and license statement.
- LICENSE: MIT terms and copyright notices.
- pyproject.toml and setup.py: package layout, version 7.0.0.dev0, and build dependencies.
- lib/yaml/__init__.py: public load, safe_load, dump, and safe_dump APIs.
- lib/yaml/constructor.py: SafeConstructor, merge flattening, constructor registration, and mapping construction.
- lib/yaml/loader.py: SafeLoader composition from the reader/scanner/parser/composer/constructor/resolver layers.
- lib/yaml/representer.py: safe representation support used by safe dumping.
- tests/test_merge.py and tests/test_dump_load.py: existing loader behavior and regression-test style.

The task objective is an independent configuration workflow based on those
real APIs: a safe recursive mapping overlay with explicit deletion, list
policies, copy isolation, and a command-line reproduction. It is not derived
from an issue, pull request, benchmark specification, old task, or solution.

## Baseline evidence

At the pinned checkout, with PYTHONPATH=lib, python3 imported PyYAML
7.0.0.dev0 and yaml.safe_load('a: 1\n') returned {'a': 1}. Importing
yaml.config_overlay failed with ModuleNotFoundError, establishing the feature
gap. The authored package adds no dependency or network requirement.

## Oracle repair evidence

Independent container review reproduced the pre-repair oracle bug with:

    PYTHONPATH=/app/pyyaml/lib python3 -c 'from yaml.config_overlay import DELETE, apply_overlay; print(apply_overlay({}, {"new": [DELETE]})); print(apply_overlay({}, {"new": {"gone": DELETE}}))'

The old oracle returned {'new': [DELETE]} and {'new': {'gone': DELETE}},
respectively. The repaired oracle traverses absent subtrees, rejects DELETE
directly in sequences or as mapping keys, applies deletion in nested mappings,
and rejects cyclic alias graphs.
