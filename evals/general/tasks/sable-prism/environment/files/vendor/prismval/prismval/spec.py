"""Task-spec loading for prismval (JSON configs)."""

import json

REQUIRED_KEYS = (
    "task_name",
    "choices",
    "model_path",
    "text_column",
    "gold_map",
    "prompt_template",
)


class TaskSpec:
    """A parsed task configuration."""

    def __init__(self, data):
        if not isinstance(data, dict):
            raise ValueError("task config must be a JSON object")
        missing = [k for k in REQUIRED_KEYS if k not in data]
        if missing:
            raise ValueError("task config missing keys: %s" % ", ".join(missing))
        self.task_name = str(data["task_name"])
        self.choices = [str(c) for c in data["choices"]]
        if len(self.choices) < 2 or len(set(self.choices)) != len(self.choices):
            raise ValueError("choices must be a list of distinct strings")
        self.model_path = str(data["model_path"])
        self.text_column = str(data["text_column"])
        self.prompt_template = str(data["prompt_template"])
        if "{text}" not in self.prompt_template:
            raise ValueError("prompt_template must contain a {text} placeholder")
        gm = data["gold_map"]
        if not isinstance(gm, dict):
            raise ValueError("gold_map must be a JSON object")
        self.gold_map = {str(k): v for k, v in gm.items()}


def load_spec(path):
    with open(path, "r", encoding="utf-8") as fh:
        return TaskSpec(json.load(fh))
