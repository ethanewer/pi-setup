#!/usr/bin/env python3
"""Register the classification task from /app/tasks.yaml into the harness.

Imports the installed `granite_eval` harness package, parses the YAML task
spec, confirms the mandated prompt template renders, and persists a small
registry manifest so the task is "registered" for evaluation.
"""
import json
import sys

sys.path.insert(0, "/app/harness")
from granite_eval import load_task_spec, render_prompt

SPEC_PATH = "/app/tasks.yaml"
REGISTRY_PATH = "/app/tasks_registry.json"


def main():
    spec = load_task_spec(SPEC_PATH)
    assert spec.n_classes == 4 and len(spec.choices) == 4, "bad task spec"
    sample = {"query": "keel lode fjord", "title": "bay cove"}
    rendered = render_prompt(spec, sample)  # template must be usable
    assert "{title}" not in rendered and "{query}" not in rendered, "template not rendered"

    registry = {
        "task": spec.task_name,
        "choices": spec.choices,
        "n_classes": spec.n_classes,
        "prompt_renders": True,
        "gold_selector": spec.doc_to_choice,
        "model": spec.model_path,
    }
    with open(REGISTRY_PATH, "w") as f:
        json.dump(registry, f, indent=2)
    print("registered task:", spec.task_name)
    return 0


if __name__ == "__main__":
    sys.exit(main())