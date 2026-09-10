#!/usr/bin/env python3
"""Fixture generator for the hopper-wicket release-pipeline task.

Builds small but real git repositories (a package called ``seabolt``, a
scheduled fixture-sync tool) with incremental history, conventional-commit
messages, release tags, and a passing stdlib unittest suite.  For the hidden
grading scenarios it also derives the exact outputs the release-rule contract
demands and writes them as expected files, so the fixtures and the verifier's
expectations are defined by one piece of code.

Usage:
    gen_repo.py visible <out-repo-dir>          # build only (visible fixture)
    gen_repo.py <scenario> <out-dir>            # build <out-dir>/repo and write
                                                #   <out-dir>/expected_version.txt
                                                #   <out-dir>/expected_changelog.md
    gen_repo.py <scenario> <out-dir> --check-suite   # also run the test suite

Scenarios: visible, h1, h2, h3
"""

import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# File contents.  Content versions are cumulative: a later version of a module
# is the earlier one plus the new behaviour, so any mix of versions is a
# plausible intermediate state.
# ---------------------------------------------------------------------------

R1 = """# seabolt

Seabolt replays scheduled fixture updates from a JSON manifest, applying
routing overrides read from a local configuration file.

## Layout

- `src/seabolt/` — the package
- `tests/` — stdlib unittest suite
- `data/defaults.json` — shipped default routing table

## Development

    make test
"""

R2 = """# seabolt

Seabolt replays scheduled fixture updates from a JSON manifest, applying
routing overrides read from a local configuration file.

## Layout

- `src/seabolt/` — the package
- `tests/` — stdlib unittest suite
- `data/defaults.json` — shipped default routing table

## Development

    make test

## Toolchain

The dev container is pinned to Ubuntu 24.04 LTS.  Keep toolchain changes in
separate pull requests so release candidates stay reproducible.
"""

R3 = """# seabolt

[![CI](https://ci.example.invalid/seabolt/badge.svg)](https://ci.example.invalid/seabolt)

Seabolt replays scheduled fixture updates from a JSON manifest, applying
routing overrides read from a local configuration file.

## Layout

- `src/seabolt/` — the package
- `tests/` — stdlib unittest suite
- `data/defaults.json` — shipped default routing table

## Development

    make test

## Toolchain

The dev container is pinned to Ubuntu 24.04 LTS.  Keep toolchain changes in
separate pull requests so release candidates stay reproducible.
"""

R4 = """# seabolt

[![CI](https://ci.example.invalid/seabolt/badge.svg)](https://ci.example.invalid/seabolt)

Seabolt replays scheduled fixture updates from a JSON manifest, applying
routing overrides read from a local configuration file.

## Layout

- `src/seabolt/` — the package
- `tests/` — stdlib unittest suite
- `data/defaults.json` — shipped default routing table

## Development

    make test

## Toolchain

The dev container is pinned to Ubuntu 24.04 LTS.  Keep toolchain changes in
separate pull requests so release candidates stay reproducible.

## Manifest slots

`entries[].slot` is a non-negative integer.  An entry becomes ready once the
highest slot already replayed is strictly smaller than the entry's slot;
entries with equal slots replay together in name order.
"""

M1 = """PYTHON ?= python3

.PHONY: test

test:
	PYTHONPATH=src $(PYTHON) -m unittest discover -s tests -t .
"""

M2 = """PYTHON ?= python3

.PHONY: test lint

test:
	PYTHONPATH=src $(PYTHON) -m unittest discover -s tests -t .

lint:
	$(PYTHON) -m py_compile src/seabolt/*.py
"""

P = """[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "seabolt"
version = "0.3.0"
description = "Scheduled fixture updater with routing overrides"
requires-python = ">=3.10"

[tool.setuptools.packages.find]
where = ["src"]
"""

G = """.gitignore
__pycache__/
*.pyc
"""

D = """{"routing": {"default": "canary", "canary": ["blue", "green"], "stable": ["red"]}}
"""

I = '''"""Seabolt: scheduled fixture updater with routing overrides."""

__version__ = "0.3.0"
'''

C1 = '''"""Configuration handling for seabolt."""

import json
from pathlib import Path


class ConfigError(RuntimeError):
    """Raised when a configuration file cannot be interpreted."""


def load_config(path, overrides=None):
    """Load a JSON configuration file and merge CLI overrides on top."""
    p = Path(path)
    if not p.is_file():
        raise ConfigError(f"config not found: {path}")
    try:
        with p.open() as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ConfigError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(cfg, dict):
        raise ConfigError(f"config root must be an object: {path}")
    merged = dict(cfg)
    if overrides:
        merged.update(overrides)
    return merged
'''

C2 = '''"""Configuration handling for seabolt."""

import json
from pathlib import Path


class ConfigError(RuntimeError):
    """Raised when a configuration file cannot be interpreted."""


def load_config(path, overrides=None):
    """Load a JSON configuration file and merge CLI overrides on top."""
    p = Path(path)
    if not p.is_file():
        raise ConfigError(f"config not found: {path}")
    try:
        with p.open() as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ConfigError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(cfg, dict):
        raise ConfigError(f"config root must be an object: {path}")
    merged = dict(cfg)
    if overrides:
        merged.update(overrides)
    return merged


def flatten_overrides(items):
    """Turn ``key=value`` CLI strings into an override dict."""
    flat = {}
    for item in items or []:
        if "=" not in item:
            raise ConfigError(f"override must be key=value, got {item!r}")
        key, value = item.split("=", 1)
        flat[key.strip()] = value.strip()
    return flat
'''

C3 = '''"""Configuration handling for seabolt."""

import json
from pathlib import Path


class ConfigError(RuntimeError):
    """Raised when a configuration file cannot be interpreted."""


def load_config(path, overrides=None):
    """Load a JSON configuration file and merge CLI overrides on top."""
    p = Path(path)
    if not p.is_file():
        raise ConfigError(f"config not found: {path}")
    try:
        with p.open() as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ConfigError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(cfg, dict):
        raise ConfigError(f"config root must be an object: {path}")
    routing = cfg.get("routing")
    if routing is not None and not isinstance(routing, dict):
        raise ConfigError(f"config 'routing' must be an object: {path}")
    merged = dict(cfg)
    if overrides:
        merged.update(overrides)
    return merged


def flatten_overrides(items):
    """Turn ``key=value`` CLI strings into an override dict."""
    flat = {}
    for item in items or []:
        if "=" not in item:
            raise ConfigError(f"override must be key=value, got {item!r}")
        key, value = item.split("=", 1)
        flat[key.strip()] = value.strip()
    return flat
'''

C4 = '''"""Configuration handling for seabolt."""

import json
from pathlib import Path


class ConfigError(RuntimeError):
    """Raised when a configuration file cannot be interpreted."""


def load_config(path, overrides=None):
    """Load a JSON configuration file and merge CLI overrides on top.

    Unknown override keys are silently ignored: an override can only adjust a
    knob the configuration file already declares.
    """
    p = Path(path)
    if not p.is_file():
        raise ConfigError(f"config not found: {path}")
    try:
        with p.open() as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ConfigError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(cfg, dict):
        raise ConfigError(f"config root must be an object: {path}")
    routing = cfg.get("routing")
    if routing is not None and not isinstance(routing, dict):
        raise ConfigError(f"config 'routing' must be an object: {path}")
    merged = dict(cfg)
    if overrides:
        for key, value in overrides.items():
            if key in merged:
                merged[key] = value
    return merged


def flatten_overrides(items):
    """Turn ``key=value`` CLI strings into an override dict."""
    flat = {}
    for item in items or []:
        if "=" not in item:
            raise ConfigError(f"override must be key=value, got {item!r}")
        key, value = item.split("=", 1)
        flat[key.strip()] = value.strip()
    return flat
'''

L1 = '''"""Manifest parsing and validation."""

import json
from pathlib import Path


class ManifestError(RuntimeError):
    """Raised when a manifest cannot be parsed or validated."""


def load_manifest(path):
    """Load and validate a manifest file.

    The manifest is a JSON object with an ``entries`` list.  Each entry is an
    object with a non-empty ``name`` and an integer ``slot`` (>= 0).
    """
    p = Path(path)
    try:
        with p.open() as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("entries"), list):
        raise ManifestError(f"manifest {path} must be a JSON object with 'entries'")
    entries = []
    for item in doc["entries"]:
        if not isinstance(item, dict):
            raise ManifestError(f"manifest entry is not an object in {path}")
        if not isinstance(item.get("name"), str) or not item["name"]:
            raise ManifestError(f"manifest entry needs a non-empty 'name' in {path}")
        slot = item.get("slot", 0)
        if not isinstance(slot, int) or isinstance(slot, bool) or slot < 0:
            raise ManifestError(
                f"manifest entry {item.get('name')!r} has an invalid 'slot' in {path}")
        entries.append({"name": item["name"], "slot": slot})
    return entries
'''

L2 = '''"""Manifest parsing and validation."""

import json
from pathlib import Path


class ManifestError(RuntimeError):
    """Raised when a manifest cannot be parsed or validated."""


def load_manifest(path):
    """Load and validate a manifest file.

    The manifest is a JSON object with an ``entries`` list.  Each entry is an
    object with a non-empty ``name`` and an integer ``slot`` (>= 0).
    """
    p = Path(path)
    try:
        with p.open() as fh:
            raw = fh.read().replace("\\r", "")
            doc = json.loads(raw.lstrip("\\ufeff"))
    except (OSError, ValueError) as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("entries"), list):
        raise ManifestError(f"manifest {path} must be a JSON object with 'entries'")
    entries = []
    for item in doc["entries"]:
        if not isinstance(item, dict):
            raise ManifestError(f"manifest entry is not an object in {path}")
        if not isinstance(item.get("name"), str) or not item["name"]:
            raise ManifestError(f"manifest entry needs a non-empty 'name' in {path}")
        slot = item.get("slot", 0)
        if not isinstance(slot, int) or isinstance(slot, bool) or slot < 0:
            raise ManifestError(
                f"manifest entry {item.get('name')!r} has an invalid 'slot' in {path}")
        entries.append({"name": item["name"], "slot": slot})
    return entries
'''

L3 = '''"""Manifest parsing and validation."""

import json
import os
from pathlib import Path


class ManifestError(RuntimeError):
    """Raised when a manifest cannot be parsed or validated."""


_CACHE = {}


def load_manifest(path):
    """Load and validate a manifest file.

    The manifest is a JSON object with an ``entries`` list.  Each entry is an
    object with a non-empty ``name`` and an integer ``slot`` (>= 0).  Parsed
    manifests are memoised on (path, mtime) so repeated engine construction
    does not re-read the file.
    """
    p = Path(path)
    try:
        stamp = os.path.getmtime(path)
    except OSError:
        raise ManifestError(f"cannot read manifest {path}") from None
    cached = _CACHE.get(path)
    if cached is not None and cached[0] == stamp:
        return cached[1]
    try:
        with p.open() as fh:
            raw = fh.read().replace("\\r", "")
            doc = json.loads(raw.lstrip("\\ufeff"))
    except (OSError, ValueError) as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("entries"), list):
        raise ManifestError(f"manifest {path} must be a JSON object with 'entries'")
    entries = []
    for item in doc["entries"]:
        if not isinstance(item, dict):
            raise ManifestError(f"manifest entry is not an object in {path}")
        if not isinstance(item.get("name"), str) or not item["name"]:
            raise ManifestError(f"manifest entry needs a non-empty 'name' in {path}")
        slot = item.get("slot", 0)
        if not isinstance(slot, int) or isinstance(slot, bool) or slot < 0:
            raise ManifestError(
                f"manifest entry {item.get('name')!r} has an invalid 'slot' in {path}")
        entries.append({"name": item["name"], "slot": slot})
    _CACHE[path] = (stamp, entries)
    return entries
'''

L4 = '''"""Manifest parsing and validation."""

import json
import os
from pathlib import Path


class ManifestError(RuntimeError):
    """Raised when a manifest cannot be parsed or validated."""


_CACHE = {}


def load_manifest(path):
    """Load and validate a manifest file.

    The manifest is a JSON object with a top-level ``format`` key (the tagged
    schema name) and an ``entries`` list.  Each entry is an object with a
    non-empty ``name`` and an integer ``slot`` (>= 0).  Parsed manifests are
    memoised on (path, mtime) so repeated engine construction does not
    re-read the file.
    """
    p = Path(path)
    try:
        stamp = os.path.getmtime(path)
    except OSError:
        raise ManifestError(f"cannot read manifest {path}") from None
    cached = _CACHE.get(path)
    if cached is not None and cached[0] == stamp:
        return cached[1]
    try:
        with p.open() as fh:
            raw = fh.read().replace("\\r", "")
            doc = json.loads(raw.lstrip("\\ufeff"))
    except (OSError, ValueError) as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("entries"), list):
        raise ManifestError(f"manifest {path} must be a JSON object with 'entries'")
    if not isinstance(doc.get("format"), str) or not doc["format"]:
        raise ManifestError(
            f"manifest {path} must declare a top-level 'format' schema name")
    entries = []
    for item in doc["entries"]:
        if not isinstance(item, dict):
            raise ManifestError(f"manifest entry is not an object in {path}")
        if not isinstance(item.get("name"), str) or not item["name"]:
            raise ManifestError(f"manifest entry needs a non-empty 'name' in {path}")
        slot = item.get("slot", 0)
        if not isinstance(slot, int) or isinstance(slot, bool) or slot < 0:
            raise ManifestError(
                f"manifest entry {item.get('name')!r} has an invalid 'slot' in {path}")
        entries.append({"name": item["name"], "slot": slot})
    _CACHE[path] = (stamp, entries)
    return entries
'''

E1 = '''"""Fixture replay engine."""

from .loader import load_manifest


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path):
        self.entries = load_manifest(manifest_path)

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = len(self.ready(last_slot))
        return applied, len(self.entries) - applied
'''

E2 = '''"""Fixture replay engine."""

from .loader import ManifestError, load_manifest


class Engine:
    """Replays manifest entries in ascending slot order.

    A missing manifest degrades to an empty schedule instead of failing the
    daemon, so operators can run against a not-yet-published manifest.
    """

    def __init__(self, manifest_path):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = len(self.ready(last_slot))
        return applied, len(self.entries) - applied
'''

E3 = '''"""Fixture replay engine."""

from .loader import ManifestError, load_manifest


class RetryBudget:
    """Exponential backoff bookkeeping for transient fixture failures."""

    def __init__(self, max_attempts=3, base_delay_s=1.0):
        self.max_attempts = max_attempts
        self.base_delay_s = base_delay_s
        self.attempts = {}

    def delay_s(self, name):
        n = self.attempts.get(name, 0)
        return self.base_delay_s * (2 ** n)

    def backoff(self, name):
        n = self.attempts.get(name, 0) + 1
        self.attempts[name] = n
        return n < self.max_attempts


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path, budget=None):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []
        self.budget = budget or RetryBudget()

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = 0
        for entry in self.ready(last_slot):
            if self.budget.backoff(entry["name"]):
                applied += 1
        return applied, len(self.entries) - applied
'''

E4 = '''"""Fixture replay engine."""

from .loader import ManifestError, load_manifest


class RetryBudget:
    """Exponential backoff bookkeeping for transient fixture failures."""

    def __init__(self, max_attempts=3, base_delay_s=1.0):
        self.max_attempts = max_attempts
        self.base_delay_s = base_delay_s
        self.attempts = {}

    def delay_s(self, name):
        n = self.attempts.get(name, 0)
        return self.base_delay_s * (2 ** n)

    def backoff(self, name):
        n = self.attempts.get(name, 0) + 1
        self.attempts[name] = n
        return n < self.max_attempts


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path, budget=None):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []
        self.budget = budget or RetryBudget()

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def plan(self, last_slot=None):
        """JSON-serialisable plan for the ready entries, deterministic."""
        return [{"name": e["name"], "slot": e["slot"]}
                for e in self.ready(last_slot)]

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = 0
        for entry in self.ready(last_slot):
            if self.budget.backoff(entry["name"]):
                applied += 1
        return applied, len(self.entries) - applied
'''

E5 = '''"""Fixture replay engine."""

import json

from .loader import ManifestError, load_manifest


class RetryBudget:
    """Exponential backoff bookkeeping for transient fixture failures."""

    def __init__(self, max_attempts=3, base_delay_s=1.0):
        self.max_attempts = max_attempts
        self.base_delay_s = base_delay_s
        self.attempts = {}

    def delay_s(self, name):
        n = self.attempts.get(name, 0)
        return self.base_delay_s * (2 ** n)

    def backoff(self, name):
        n = self.attempts.get(name, 0) + 1
        self.attempts[name] = n
        return n < self.max_attempts


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path, budget=None):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []
        self.budget = budget or RetryBudget()

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def plan(self, last_slot=None):
        """JSON-serialisable plan for the ready entries, deterministic."""
        return [{"name": e["name"], "slot": e["slot"]}
                for e in self.ready(last_slot)]

    def batched(self, size, last_slot=None):
        """Yield ready entries in slices of *size* (batched replay window)."""
        ready = self.ready(last_slot)
        for i in range(0, len(ready) + 1, size):
            chunk = ready[i:i + size]
            if not chunk:
                continue
            yield chunk

    @staticmethod
    def jsonl_marshal(entries):
        """Render ready entries as newline-delimited JSON."""
        return "\\n".join(json.dumps(e) for e in entries) + "\\n"

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = 0
        for entry in self.ready(last_slot):
            if self.budget.backoff(entry["name"]):
                applied += 1
        return applied, len(self.entries) - applied
'''

E6 = '''"""Fixture replay engine."""

import json

from .loader import ManifestError, load_manifest


class RetryBudget:
    """Exponential backoff bookkeeping for transient fixture failures."""

    def __init__(self, max_attempts=3, base_delay_s=1.0):
        self.max_attempts = max_attempts
        self.base_delay_s = base_delay_s
        self.attempts = {}

    def delay_s(self, name):
        n = self.attempts.get(name, 0)
        return self.base_delay_s * (2 ** n)

    def backoff(self, name):
        n = self.attempts.get(name, 0) + 1
        self.attempts[name] = n
        return n < self.max_attempts


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path, budget=None):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []
        self.budget = budget or RetryBudget()

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def plan(self, last_slot=None):
        """JSON-serialisable plan for the ready entries, deterministic."""
        return [{"name": e["name"], "slot": e["slot"]}
                for e in self.ready(last_slot)]

    def batched(self, size, last_slot=None):
        """Yield ready entries in slices of *size* (batched replay window).

        The window boundary is exact: a multiple of the batch size produces no
        trailing empty batch.
        """
        ready = self.ready(last_slot)
        for i in range(0, len(ready), size):
            yield ready[i:i + size]

    @staticmethod
    def jsonl_marshal(entries):
        """Render ready entries as newline-delimited JSON."""
        if not entries:
            return ""
        return "".join(json.dumps(e) + "\\n" for e in entries)

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = 0
        for entry in self.ready(last_slot):
            if self.budget.backoff(entry["name"]):
                applied += 1
        return applied, len(self.entries) - applied
'''

E7 = '''"""Fixture replay engine."""

import json

from .loader import ManifestError, load_manifest


class RetryBudget:
    """Exponential backoff bookkeeping for transient fixture failures."""

    def __init__(self, max_attempts=3, base_delay_s=1.0):
        self.max_attempts = max_attempts
        self.base_delay_s = base_delay_s
        self.attempts = {}

    def delay_s(self, name):
        n = self.attempts.get(name, 0)
        return self.base_delay_s * (2 ** n)

    def backoff(self, name):
        n = self.attempts.get(name, 0) + 1
        self.attempts[name] = n
        return n < self.max_attempts


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path, budget=None):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []
        self.budget = budget or RetryBudget()

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def plan(self, last_slot=None):
        """JSON-serialisable plan for the ready entries, deterministic."""
        return [{"name": e["name"], "slot": e["slot"]}
                for e in self.ready(last_slot)]

    def batched(self, size, last_slot=None, continue_ok=False):
        """Yield ready entries in slices of *size* (batched replay window).

        Continuing past the first window requires an explicit ``continue_ok``
        flag so an accidental re-run cannot drain a live window.
        """
        ready = self.ready(last_slot)
        if len(ready) > size and not continue_ok:
            raise ValueError("batch continuation requires an explicit continue flag")
        for i in range(0, len(ready), size):
            yield ready[i:i + size]

    @staticmethod
    def jsonl_marshal(entries):
        """Render ready entries as newline-delimited JSON."""
        if not entries:
            return ""
        return "".join(json.dumps(e) + "\\n" for e in entries)

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = 0
        for entry in self.ready(last_slot):
            if self.budget.backoff(entry["name"]):
                applied += 1
        return applied, len(self.entries) - applied
'''

E8 = '''"""Fixture replay engine."""

import json

from .loader import ManifestError, load_manifest


class RetryBudget:
    """Exponential backoff bookkeeping for transient fixture failures."""

    def __init__(self, max_attempts=3, base_delay_s=1.0):
        self.max_attempts = max_attempts
        self.base_delay_s = base_delay_s
        self.attempts = {}

    def delay_s(self, name):
        n = self.attempts.get(name, 0)
        return self.base_delay_s * (2 ** n)

    def backoff(self, name):
        n = self.attempts.get(name, 0) + 1
        self.attempts[name] = n
        return n < self.max_attempts


class Engine:
    """Replays manifest entries in ascending slot order."""

    def __init__(self, manifest_path, budget=None):
        try:
            self.entries = load_manifest(manifest_path)
        except (ManifestError, OSError):
            self.entries = []
        self.budget = budget or RetryBudget()

    def ready(self, last_slot=None):
        """Entries whose slot is strictly greater than *last_slot*, ordered by
        slot then name."""
        pool = [e for e in self.entries
                if last_slot is None or e["slot"] > last_slot]
        pool.sort(key=lambda e: (e["slot"], e["name"]))
        return pool

    def plan(self, last_slot=None):
        """JSON-serialisable plan for the ready entries, deterministic."""
        return [{"name": e["name"], "slot": e["slot"]}
                for e in self.ready(last_slot)]

    def batched(self, size, last_slot=None, continue_ok=False):
        """Yield ready entries in slices of *size* (batched replay window).

        Continuing past the first window requires an explicit ``continue_ok``
        flag so an accidental re-run cannot drain a live window.
        """
        ready = self.ready(last_slot)
        if len(ready) > size and not continue_ok:
            raise ValueError("batch continuation requires an explicit continue flag")
        for i in range(0, len(ready), size):
            yield ready[i:i + size]

    @staticmethod
    def jsonl_marshal(entries):
        """Render ready entries as newline-delimited JSON."""
        if not entries:
            return ""
        return "".join(json.dumps(e) + "\\n" for e in entries)

    def export_plan_json(self, last_slot=None):
        """Render the whole ready plan as a single JSON document."""
        return json.dumps({"plan": self.plan(last_slot)})

    def run_ready(self, last_slot=None):
        """Return (applied, skipped) counts for the ready entries."""
        applied = 0
        for entry in self.ready(last_slot):
            if self.budget.backoff(entry["name"]):
                applied += 1
        return applied, len(self.entries) - applied
'''

K1 = '''"""Command-line entrypoint for seabolt."""

import argparse
import sys

from .config import load_config
from .engine import Engine


def main(argv=None):
    parser = argparse.ArgumentParser(prog="seabolt")
    parser.add_argument("--config", default="seabolt.json")
    parser.add_argument("manifest")
    args = parser.parse_args(argv)
    load_config(args.config)
    Engine(args.manifest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
'''

K2 = '''"""Command-line entrypoint for seabolt."""

import argparse
import sys

from .config import load_config
from .engine import Engine


def main(argv=None):
    parser = argparse.ArgumentParser(prog="seabolt")
    parser.add_argument("--config", default="seabolt.json")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan without applying it")
    parser.add_argument("manifest")
    args = parser.parse_args(argv)
    cfg = load_config(args.config)
    engine = Engine(args.manifest)
    if args.dry_run:
        print("\\n".join(e["name"] for e in engine.plan()))
        return 0
    engine.run_ready()
    return 0


if __name__ == "__main__":
    sys.exit(main())
'''

CI_YML = """name: ci
on:
  pull_request:
    paths: ['src/**', 'tests/**']
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make test
"""

TI = ""

T1 = '''import json
import os
import tempfile
import unittest

from seabolt.config import ConfigError, load_config


class ConfigTest(unittest.TestCase):
    def test_loads_json_and_merges_overrides(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"retries": 1, "timeout_s": 5.0}, fh)
            cfg = load_config(path, overrides={"retries": 9})
            self.assertEqual(cfg["retries"], 9)
            self.assertEqual(cfg["timeout_s"], 5.0)

    def test_missing_file_raises(self):
        with self.assertRaises(ConfigError):
            load_config("/nonexistent/nope.json")

    def test_non_object_root_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                fh.write("[1, 2]")
            with self.assertRaises(ConfigError):
                load_config(path)
'''

T2 = '''import json
import os
import tempfile
import unittest

from seabolt.config import ConfigError, flatten_overrides, load_config


class ConfigTest(unittest.TestCase):
    def test_loads_json_and_merges_overrides(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"retries": 1, "timeout_s": 5.0}, fh)
            cfg = load_config(path, overrides={"retries": 9})
            self.assertEqual(cfg["retries"], 9)
            self.assertEqual(cfg["timeout_s"], 5.0)

    def test_missing_file_raises(self):
        with self.assertRaises(ConfigError):
            load_config("/nonexistent/nope.json")

    def test_non_object_root_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                fh.write("[1, 2]")
            with self.assertRaises(ConfigError):
                load_config(path)

    def test_flatten_overrides(self):
        self.assertEqual(
            flatten_overrides(["retries=9", "timeout_s=30"]),
            {"retries": "9", "timeout_s": "30"})

    def test_flatten_rejects_bare_token(self):
        with self.assertRaises(ConfigError):
            flatten_overrides(["retries"])
'''

T3 = '''import json
import os
import tempfile
import unittest

from seabolt.config import ConfigError, flatten_overrides, load_config


class ConfigTest(unittest.TestCase):
    def test_loads_json_and_merges_overrides(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"retries": 1, "timeout_s": 5.0}, fh)
            cfg = load_config(path, overrides={"retries": 9})
            self.assertEqual(cfg["retries"], 9)
            self.assertEqual(cfg["timeout_s"], 5.0)

    def test_missing_file_raises(self):
        with self.assertRaises(ConfigError):
            load_config("/nonexistent/nope.json")

    def test_non_object_root_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                fh.write("[1, 2]")
            with self.assertRaises(ConfigError):
                load_config(path)

    def test_flatten_overrides(self):
        self.assertEqual(
            flatten_overrides(["retries=9", "timeout_s=30"]),
            {"retries": "9", "timeout_s": "30"})

    def test_flatten_rejects_bare_token(self):
        with self.assertRaises(ConfigError):
            flatten_overrides(["retries"])

    def test_routing_must_be_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"routing": ["canary"]}, fh)
            with self.assertRaises(ConfigError):
                load_config(path)
'''

T4 = '''import json
import os
import tempfile
import unittest

from seabolt.config import ConfigError, flatten_overrides, load_config


class ConfigTest(unittest.TestCase):
    def test_loads_json_and_merges_overrides(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"retries": 1, "timeout_s": 5.0}, fh)
            cfg = load_config(path, overrides={"retries": 9})
            self.assertEqual(cfg["retries"], 9)
            self.assertEqual(cfg["timeout_s"], 5.0)

    def test_missing_file_raises(self):
        with self.assertRaises(ConfigError):
            load_config("/nonexistent/nope.json")

    def test_non_object_root_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                fh.write("[1, 2]")
            with self.assertRaises(ConfigError):
                load_config(path)

    def test_flatten_overrides(self):
        self.assertEqual(
            flatten_overrides(["retries=9", "timeout_s=30"]),
            {"retries": "9", "timeout_s": "30"})

    def test_flatten_rejects_bare_token(self):
        with self.assertRaises(ConfigError):
            flatten_overrides(["retries"])

    def test_routing_must_be_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"routing": ["canary"]}, fh)
            with self.assertRaises(ConfigError):
                load_config(path)

    def test_unknown_override_keys_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "cfg.json")
            with open(path, "w") as fh:
                json.dump({"retries": 1}, fh)
            cfg = load_config(path, overrides={"retries": 5, "verbose": True})
            self.assertEqual(cfg["retries"], 5)
            self.assertNotIn("verbose", cfg)
'''

U1 = '''import json
import os
import tempfile
import unittest

from seabolt.loader import ManifestError, load_manifest


def write(tmp, doc):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump(doc, fh)
    return path


class LoaderTest(unittest.TestCase):
    def test_valid_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write(tmp, {"entries": [
                {"name": "us-eu", "slot": 1},
                {"name": "ap-sg", "slot": 3},
            ]}))
            self.assertEqual([e["name"] for e in entries], ["us-eu", "ap-sg"])

    def test_default_slot_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write(tmp, {"entries": [{"name": "x"}]}))
            self.assertEqual(entries[0]["slot"], 0)

    def test_missing_entries_key_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"slots": []}))

    def test_negative_slot_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"entries": [{"name": "x", "slot": -1}]}))
'''

U2 = '''import json
import os
import tempfile
import unittest

from seabolt.loader import ManifestError, load_manifest


def write(tmp, doc):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump(doc, fh)
    return path


class LoaderTest(unittest.TestCase):
    def test_valid_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write(tmp, {"entries": [
                {"name": "us-eu", "slot": 1},
                {"name": "ap-sg", "slot": 3},
            ]}))
            self.assertEqual([e["name"] for e in entries], ["us-eu", "ap-sg"])

    def test_default_slot_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write(tmp, {"entries": [{"name": "x"}]}))
            self.assertEqual(entries[0]["slot"], 0)

    def test_missing_entries_key_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"slots": []}))

    def test_negative_slot_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"entries": [{"name": "x", "slot": -1}]}))

    def test_crlf_line_endings_tolerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "manifest.json")
            with open(path, "wb") as fh:
                fh.write(b'{\\r\\n  "entries": [\\r\\n    {"name": "x", "slot": 1}\\r\\n  ]\\r\\n}')
            entries = load_manifest(path)
            self.assertEqual([e["name"] for e in entries], ["x"])
'''

U3 = '''import json
import os
import tempfile
import unittest

from seabolt.loader import ManifestError, load_manifest


def write(tmp, doc):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump(doc, fh)
    return path


class LoaderTest(unittest.TestCase):
    def test_valid_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write(tmp, {"entries": [
                {"name": "us-eu", "slot": 1},
                {"name": "ap-sg", "slot": 3},
            ]}))
            self.assertEqual([e["name"] for e in entries], ["us-eu", "ap-sg"])

    def test_default_slot_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write(tmp, {"entries": [{"name": "x"}]}))
            self.assertEqual(entries[0]["slot"], 0)

    def test_missing_entries_key_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"slots": []}))

    def test_negative_slot_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"entries": [{"name": "x", "slot": -1}]}))

    def test_crlf_line_endings_tolerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "manifest.json")
            with open(path, "wb") as fh:
                fh.write(b'{\\r\\n  "entries": [\\r\\n    {"name": "x", "slot": 1}\\r\\n  ]\\r\\n}')
            entries = load_manifest(path)
            self.assertEqual([e["name"] for e in entries], ["x"])

    def test_parsed_manifests_are_memoised(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, {"entries": [{"name": "x", "slot": 1}]})
            first = load_manifest(path)
            second = load_manifest(path)
            self.assertIs(first, second)
'''

U4 = '''import json
import os
import tempfile
import unittest

from seabolt.loader import ManifestError, load_manifest


def write(tmp, doc):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump(doc, fh)
    return path


def write_tagged(tmp, entries):
    return write(tmp, {"format": "seabolt/v2", "entries": entries})


class LoaderTest(unittest.TestCase):
    def test_valid_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write_tagged(tmp, [
                {"name": "us-eu", "slot": 1},
                {"name": "ap-sg", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in entries], ["us-eu", "ap-sg"])

    def test_default_slot_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = load_manifest(write_tagged(tmp, [{"name": "x"}]))
            self.assertEqual(entries[0]["slot"], 0)

    def test_missing_format_key_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"entries": [{"name": "x"}]}))

    def test_missing_entries_key_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write(tmp, {"format": "seabolt/v2"}))

    def test_negative_slot_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ManifestError):
                load_manifest(write_tagged(tmp, [{"name": "x", "slot": -1}]))

    def test_crlf_line_endings_tolerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "manifest.json")
            with open(path, "wb") as fh:
                fh.write(b'{\\r\\n  "format": "seabolt/v2",\\r\\n  "entries": [\\r\\n    {"name": "x", "slot": 1}\\r\\n  ]\\r\\n}')
            entries = load_manifest(path)
            self.assertEqual([e["name"] for e in entries], ["x"])

    def test_parsed_manifests_are_memoised(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_tagged(tmp, [{"name": "x", "slot": 1}])
            first = load_manifest(path)
            second = load_manifest(path)
            self.assertIs(first, second)
'''

V1 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]))
            applied, skipped = engine.run_ready(1)
            self.assertEqual(applied, 1)
            self.assertEqual(skipped, 1)
'''

V2 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])
'''

V3 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine, RetryBudget


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_honours_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]), budget=RetryBudget(max_attempts=2))
            applied, _ = engine.run_ready(0)
            self.assertEqual(applied, 2)
            applied, _ = engine.run_ready(-1)
            self.assertEqual(applied, 0)

    def test_backoff_sequence(self):
        budget = RetryBudget(max_attempts=5, base_delay_s=2.0)
        self.assertEqual(budget.delay_s("x"), 2.0)
        budget.backoff("x")
        self.assertEqual(budget.delay_s("x"), 4.0)
'''

V4 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine, RetryBudget


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_honours_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]), budget=RetryBudget(max_attempts=2))
            applied, _ = engine.run_ready(0)
            self.assertEqual(applied, 2)
            applied, _ = engine.run_ready(-1)
            self.assertEqual(applied, 0)

    def test_backoff_sequence(self):
        budget = RetryBudget(max_attempts=5, base_delay_s=2.0)
        self.assertEqual(budget.delay_s("x"), 2.0)
        budget.backoff("x")
        self.assertEqual(budget.delay_s("x"), 4.0)

    def test_plan_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
            ]))
            self.assertEqual(
                engine.plan(),
                [{"name": "a", "slot": 1}, {"name": "b", "slot": 2}])
'''

V5 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine, RetryBudget


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_honours_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]), budget=RetryBudget(max_attempts=2))
            applied, _ = engine.run_ready(0)
            self.assertEqual(applied, 2)
            applied, _ = engine.run_ready(-1)
            self.assertEqual(applied, 0)

    def test_backoff_sequence(self):
        budget = RetryBudget(max_attempts=5, base_delay_s=2.0)
        self.assertEqual(budget.delay_s("x"), 2.0)
        budget.backoff("x")
        self.assertEqual(budget.delay_s("x"), 4.0)

    def test_plan_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
            ]))
            self.assertEqual(
                engine.plan(),
                [{"name": "a", "slot": 1}, {"name": "b", "slot": 2}])

    def test_batched_slices(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
                {"name": "c", "slot": 3},
            ]))
            chunks = list(engine.batched(2))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"], ["c"]])

    def test_jsonl_marshal(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [{"name": "b", "slot": 2}]))
            blob = engine.jsonl_marshal(engine.ready())
            self.assertEqual(blob, '{"name": "b", "slot": 2}\\n')
'''

V6 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine, RetryBudget


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_honours_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]), budget=RetryBudget(max_attempts=2))
            applied, _ = engine.run_ready(0)
            self.assertEqual(applied, 2)
            applied, _ = engine.run_ready(-1)
            self.assertEqual(applied, 0)

    def test_backoff_sequence(self):
        budget = RetryBudget(max_attempts=5, base_delay_s=2.0)
        self.assertEqual(budget.delay_s("x"), 2.0)
        budget.backoff("x")
        self.assertEqual(budget.delay_s("x"), 4.0)

    def test_plan_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
            ]))
            self.assertEqual(
                engine.plan(),
                [{"name": "a", "slot": 1}, {"name": "b", "slot": 2}])

    def test_batched_slices(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
                {"name": "c", "slot": 3},
            ]))
            chunks = list(engine.batched(2))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"], ["c"]])

    def test_batched_exact_boundary(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]))
            chunks = list(engine.batched(2))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"]])

    def test_jsonl_marshal(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [{"name": "b", "slot": 2}]))
            blob = engine.jsonl_marshal(engine.ready())
            self.assertEqual(blob, '{"name": "b", "slot": 2}\\n')

    def test_jsonl_marshal_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.jsonl_marshal([]), "")
'''

V7 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine, RetryBudget


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_honours_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]), budget=RetryBudget(max_attempts=2))
            applied, _ = engine.run_ready(0)
            self.assertEqual(applied, 2)
            applied, _ = engine.run_ready(-1)
            self.assertEqual(applied, 0)

    def test_backoff_sequence(self):
        budget = RetryBudget(max_attempts=5, base_delay_s=2.0)
        self.assertEqual(budget.delay_s("x"), 2.0)
        budget.backoff("x")
        self.assertEqual(budget.delay_s("x"), 4.0)

    def test_plan_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
            ]))
            self.assertEqual(
                engine.plan(),
                [{"name": "a", "slot": 1}, {"name": "b", "slot": 2}])

    def test_batched_slices(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
                {"name": "c", "slot": 3},
            ]))
            chunks = list(engine.batched(2, continue_ok=True))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"], ["c"]])

    def test_batched_requires_continue_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
                {"name": "c", "slot": 3},
            ]))
            with self.assertRaises(ValueError):
                list(engine.batched(2))
            chunks = list(engine.batched(2, continue_ok=True))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"], ["c"]])

    def test_jsonl_marshal(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [{"name": "b", "slot": 2}]))
            blob = engine.jsonl_marshal(engine.ready())
            self.assertEqual(blob, '{"name": "b", "slot": 2}\\n')

    def test_jsonl_marshal_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.jsonl_marshal([]), "")
'''

V8 = '''import json
import os
import tempfile
import unittest

from seabolt.engine import Engine, RetryBudget


def write(tmp, entries):
    path = os.path.join(tmp, "manifest.json")
    with open(path, "w") as fh:
        json.dump({"format": "seabolt/v2", "entries": entries}, fh)
    return path


class EngineTest(unittest.TestCase):
    def test_ready_filters_and_orders(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
                {"name": "c", "slot": 3},
            ]))
            self.assertEqual([e["name"] for e in engine.ready()], ["a", "b", "c"])
            self.assertEqual([e["name"] for e in engine.ready(1)], ["b", "c"])

    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.ready(), [])

    def test_missing_manifest_degrades_to_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(os.path.join(tmp, "missing.json"))
            self.assertEqual(engine.ready(), [])

    def test_run_ready_honours_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]), budget=RetryBudget(max_attempts=2))
            applied, _ = engine.run_ready(0)
            self.assertEqual(applied, 2)
            applied, _ = engine.run_ready(-1)
            self.assertEqual(applied, 0)

    def test_backoff_sequence(self):
        budget = RetryBudget(max_attempts=5, base_delay_s=2.0)
        self.assertEqual(budget.delay_s("x"), 2.0)
        budget.backoff("x")
        self.assertEqual(budget.delay_s("x"), 4.0)

    def test_plan_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "b", "slot": 2},
                {"name": "a", "slot": 1},
            ]))
            self.assertEqual(
                engine.plan(),
                [{"name": "a", "slot": 1}, {"name": "b", "slot": 2}])

    def test_batched_slices(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
                {"name": "c", "slot": 3},
            ]))
            chunks = list(engine.batched(2, continue_ok=True))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"], ["c"]])

    def test_batched_requires_continue_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
                {"name": "c", "slot": 3},
            ]))
            with self.assertRaises(ValueError):
                list(engine.batched(2))
            chunks = list(engine.batched(2, continue_ok=True))
            self.assertEqual(
                [[e["name"] for e in c] for c in chunks], [["a", "b"], ["c"]])

    def test_jsonl_marshal(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [{"name": "b", "slot": 2}]))
            blob = engine.jsonl_marshal(engine.ready())
            self.assertEqual(blob, '{"name": "b", "slot": 2}\\n')

    def test_jsonl_marshal_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, []))
            self.assertEqual(engine.jsonl_marshal([]), "")

    def test_export_plan_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = Engine(write(tmp, [
                {"name": "a", "slot": 1},
                {"name": "b", "slot": 2},
            ]))
            doc = json.loads(engine.export_plan_json())
            self.assertEqual([e["name"] for e in doc["plan"]], ["a", "b"])
'''

W1 = '''import tempfile
import unittest

from seabolt import cli


class CliTest(unittest.TestCase):
    def test_parses_manifest_argument(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = tmp + "/cfg.json"
            manifest = tmp + "/manifest.json"
            with open(cfg, "w") as fh:
                fh.write("{}")
            with open(manifest, "w") as fh:
                fh.write('{"entries": []}')
            rc = cli.main(["--config", cfg, manifest])
            self.assertEqual(rc, 0)
'''

W2 = '''import tempfile
import unittest
from unittest.mock import patch

from seabolt import cli


class CliTest(unittest.TestCase):
    def test_parses_manifest_argument(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = tmp + "/cfg.json"
            manifest = tmp + "/manifest.json"
            with open(cfg, "w") as fh:
                fh.write("{}")
            with open(manifest, "w") as fh:
                fh.write('{"format": "seabolt/v2", "entries": []}')
            rc = cli.main(["--config", cfg, manifest])
            self.assertEqual(rc, 0)

    def test_dry_run_prints_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = tmp + "/cfg.json"
            manifest = tmp + "/manifest.json"
            with open(cfg, "w") as fh:
                fh.write("{}")
            with open(manifest, "w") as fh:
                fh.write('{"format": "seabolt/v2", "entries": [{"name": "a", "slot": 1}]}')
            with patch("sys.stdout") as out:
                rc = cli.main(["--config", cfg, "--dry-run", manifest])
            self.assertEqual(rc, 0)
            written = "".join(str(c.args[0]) for c in out.write.call_args_list)
            self.assertIn("a", written)
'''

# Verify no two content names collide, and every reference exists.
_ALL = {k: v for k, v in list(globals().items())
        if isinstance(v, str) and not k.startswith("_")}

BASE_SET = [
    ("README.md", "R1"), ("Makefile", "M1"), ("pyproject.toml", "P"),
    (".gitignore", "G"), ("data/defaults.json", "D"),
    ("src/seabolt/__init__.py", "I"), ("src/seabolt/config.py", "C1"),
    ("src/seabolt/loader.py", "L1"), ("src/seabolt/engine.py", "E1"),
    ("src/seabolt/cli.py", "K1"), ("tests/__init__.py", "TI"),
    ("tests/test_config.py", "T1"), ("tests/test_loader.py", "U1"),
    ("tests/test_engine.py", "V1"), ("tests/test_cli.py", "W1"),
]

# ---------------------------------------------------------------------------
# Scenario commit plans.  Each commit: (timestamp, subject, body, ops) where
# ops is a list of ("set", path, CONTENT_NAME) | ("del", path).
# ---------------------------------------------------------------------------


def S(path, name):
    return ("set", path, name)


def D_(path):
    return ("del", path)


VISIBLE = [
    ("2024-01-02T09:00:00+0000",
     "chore: scaffold seabolt package layout", "",
     [S(p, n) for p, n in BASE_SET]),
    ("2024-01-05T11:30:00+0000",
     "feat: parse routing overrides from CLI flags", "",
     [S("src/seabolt/config.py", "C2"), S("tests/test_config.py", "T2")]),
    ("2024-01-09T14:00:00+0000",
     "fix: tolerate CRLF line endings in manifest files", "",
     [S("src/seabolt/loader.py", "L2"), S("tests/test_loader.py", "U2")]),
    ("2024-01-12T10:15:00+0000",
     "chore: pin dev container base image", "",
     [S("README.md", "R2")]),
    ("2024-02-01T09:20:00+0000",
     "feat: add retry budget with exponential backoff", "",
     [S("src/seabolt/engine.py", "E3"), S("tests/test_engine.py", "V3")]),
    ("2024-02-03T15:45:00+0000",
     "fix: order plan output for stable diffing", "",
     [S("src/seabolt/engine.py", "E4"), S("tests/test_engine.py", "V4")]),
    ("2024-02-10T12:00:00+0000",
     "chore: add CI badge to readme", "",
     [S("README.md", "R3")]),
    ("2024-02-14T08:30:00+0000",
     "docs: document the manifest slot semantic", "",
     [S("README.md", "R4")]),
]

H1 = [
    ("2024-03-01T09:00:00+0000",
     "chore: scaffold seabolt package layout", "",
     [S(p, n) for p, n in BASE_SET]),
    ("2024-03-04T10:30:00+0000",
     "feat: add batching mode to cli", "",
     [S("src/seabolt/engine.py", "E5"), S("tests/test_engine.py", "V5")]),
    ("2024-03-08T13:20:00+0000",
     "fix: guard against empty routing table", "",
     [S("src/seabolt/config.py", "C3"), S("tests/test_config.py", "T3")]),
    ("2024-03-12T09:45:00+0000",
     "chore: pin dev container base image", "",
     [S("README.md", "R2")]),
    ("2024-04-02T08:15:00+0000",
     "feat(api): add jsonl output format", "",
     [S("src/seabolt/engine.py", "E6"), S("tests/test_engine.py", "V6")]),
    ("2024-04-05T11:00:00+0000",
     "fix: make plan output deterministic", "",
     [S("src/seabolt/engine.py", "E7"), S("tests/test_engine.py", "V7")]),
    ("2024-04-09T16:40:00+0000",
     "chore: bump dev container image tag", "",
     [S("README.md", "R3")]),
    ("2024-04-15T10:05:00+0000",
     "refactor!: consolidate plan rendering in one entrypoint", "",
     [S("src/seabolt/engine.py", "E8"), S("tests/test_engine.py", "V8")]),
]

H2 = [
    ("2024-05-01T09:00:00+0000",
     "feat: bootstrap v2 manifest format", "",
     [S(p, n) for p, n in BASE_SET]),
    ("2024-05-03T12:10:00+0000",
     "fix: normalize manifest line endings", "",
     [S("src/seabolt/loader.py", "L2"), S("tests/test_loader.py", "U2")]),
    ("2024-05-06T15:30:00+0000",
     "chore: add make lint target", "",
     [S("Makefile", "M2")]),
    ("2024-05-09T10:00:00+0000",
     "docs: describe manifest schema in readme", "",
     [S("README.md", "R2")]),
    ("2024-06-01T09:05:00+0000",
     "feat(cli): add --dry-run flag", "",
     [S("src/seabolt/cli.py", "K2"), S("tests/test_cli.py", "W2")]),
    ("2024-06-04T14:20:00+0000",
     "fix(config): ignore unknown keys in override map",
     "note: this is not a breaking-change: overrides stay additive",
     [S("src/seabolt/config.py", "C4"), S("tests/test_config.py", "T4")]),
    ("2024-06-07T11:45:00+0000",
     "perf: cache manifest parsing across runs", "",
     [S("src/seabolt/loader.py", "L3"), S("tests/test_loader.py", "U3")]),
    ("2024-06-10T09:30:00+0000",
     "feat: emit execution plan as json",
     "Manifest consumers must migrate to the tagged schema before this lands.\n"
     "\n"
     "BREAKING CHANGE: the manifest schema now requires a top-level \"format\" key",
     [S("src/seabolt/loader.py", "L4"), S("tests/test_loader.py", "U4"),
      S("src/seabolt/engine.py", "E8"), S("tests/test_engine.py", "V8")]),
    ("2024-06-12T16:00:00+0000",
     "Merge pull request #104 from seabolt/dry-run",
     "Integrates the dry-run flag into the operator playbook.",
     []),
]

H3_BASE = [(p, n) for p, n in BASE_SET
           if not p.startswith("src/seabolt/cli") and p != "tests/test_cli.py"]

H3 = [
    ("2023-11-01T08:00:00+0000",
     "Import legacy fixture pipeline", "",
     [S(p, n) for p, n in H3_BASE]),
    ("2023-11-12T09:15:00+0000",
     "feat: add cli entrypoint", "",
     [S("src/seabolt/cli.py", "K1"), S("tests/test_cli.py", "W1")]),
    ("2023-11-20T14:30:00+0000",
     "fix: handle missing manifest gracefully", "",
     [S("src/seabolt/engine.py", "E2"), S("tests/test_engine.py", "V2")]),
    ("2023-11-28T10:40:00+0000",
     "chore: add changelog lint to ci", "",
     [S(".github/workflows/ci.yml", "CI_YML")]),
    ("2023-12-05T13:00:00+0000",
     "feat: add batching mode", "",
     [S("src/seabolt/engine.py", "E5"), S("tests/test_engine.py", "V5")]),
    ("2023-12-08T09:20:00+0000",
     "fix: batch window boundary off by one", "",
     [S("src/seabolt/engine.py", "E6"), S("tests/test_engine.py", "V6")]),
    ("2023-12-15T11:30:00+0000",
     "fix!: require explicit continue flag in batch mode", "",
     [S("src/seabolt/engine.py", "E7"), S("tests/test_engine.py", "V7")]),
]

SCENARIOS = {
    "visible": {"commits": VISIBLE, "tag_at": 3, "tag_name": "v0.3.0",
                "tag_msg": "Release 0.3.0"},
    "h1": {"commits": H1, "tag_at": 3, "tag_name": "v0.9.3",
           "tag_msg": "Release 0.9.3"},
    "h2": {"commits": H2, "tag_at": 3, "tag_name": "v2.4.1",
           "tag_msg": "Release 2.4.1"},
    "h3": {"commits": H3, "tag_at": 4, "tag_name": "v1.0.0-rc.1",
           "tag_msg": "Release candidate 1.0.0-rc.1"},
}

# ---------------------------------------------------------------------------
# Repository construction
# ---------------------------------------------------------------------------


def run(argv, env=None, cwd=None, check=True):
    r = subprocess.run(argv, capture_output=True, text=True, env=env, cwd=cwd)
    if check and r.returncode != 0:
        raise SystemExit(f"command failed ({r.returncode}): {' '.join(argv)}\n{r.stderr}")
    return r


def git_env(ts):
    env = dict(os.environ)
    env["GIT_AUTHOR_NAME"] = "build"
    env["GIT_AUTHOR_EMAIL"] = "build@localhost"
    env["GIT_COMMITTER_NAME"] = "build"
    env["GIT_COMMITTER_EMAIL"] = "build@localhost"
    env["GIT_AUTHOR_DATE"] = ts
    env["GIT_COMMITTER_DATE"] = ts
    return env


def build_repo(root, scenario):
    plan = SCENARIOS[scenario]
    if os.path.exists(root):
        import shutil
        shutil.rmtree(root)
    os.makedirs(root)
    run(["git", "init", "-b", "main", root])
    run(["git", "-C", root, "config", "user.name", "build"])
    run(["git", "-C", root, "config", "user.email", "build@localhost"])
    files = {}
    for i, (ts, subj, body, ops) in enumerate(plan["commits"]):
        for op, path, name in ops:
            if op == "set":
                files[path] = _ALL[name]
            elif op == "del":
                fp = os.path.join(root, path)
                if os.path.exists(fp):
                    os.remove(fp)
                files.pop(path, None)
        # materialise the full tree for this commit
        for path, content in files.items():
            fp = os.path.join(root, path)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as fh:
                fh.write(content)
        argv = ["git", "-C", root, "add", "-A"]
        run(argv)
        if not ops:
            argv = ["git", "-C", root, "commit", "--allow-empty", "-m", subj]
            if body:
                argv += ["-m", body]
        else:
            argv = ["git", "-C", root, "commit", "-m", subj]
            if body:
                argv += ["-m", body]
        run(argv, env=git_env(ts))
        if i == plan["tag_at"]:
            run(["git", "-C", root, "tag", "-a", plan["tag_name"],
                 "-m", plan["tag_msg"]], env=git_env(ts))
    return root


def run_suite(root):
    env = dict(os.environ)
    env["PYTHONPATH"] = os.path.abspath(os.path.join(root, "src"))
    r = subprocess.run(["python3", "-m", "unittest", "discover", "-s",
                        "tests", "-t", "."],
                       capture_output=True, text=True, cwd=root, env=env)
    return r


# ---------------------------------------------------------------------------
# Canonical release-rule derivation (mirrors the contract in instruction.md;
# also the reference implementation for the hidden expected files).
# ---------------------------------------------------------------------------

CONV = re.compile(r"^([a-z]+)(?:\(([^()]*)\))?(!)?: (.*)$")
BREAK_LINE = re.compile(r"^\s*breaking[ -]change:", re.IGNORECASE)


def git(repo, *args):
    return run(["git", "-C", repo, *args]).stdout


def derive(repo):
    """Return (version, changelog_text, date) or (None, None, date)."""
    releases = []
    for t in git(repo, "tag").splitlines():
        m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", t.strip())
        if m:
            releases.append((tuple(int(g) for g in m.groups()), t.strip()))
    base = max(releases)[0] if releases else (0, 0, 0)
    base_tag = None if not releases else max(releases)[1]

    fmt = "%x1e%H%x1f%ct%x1f%B"
    if base_tag:
        raw = git(repo, "log", "--format=" + fmt, f"{base_tag}..HEAD")
    else:
        raw = git(repo, "log", "--format=" + fmt, "HEAD")
    date = git(repo, "log", "-1", "--format=%cd", "--date=short", "HEAD").strip()

    commits = []
    for rec in raw.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        sha, ts, msg = rec.split("\x1f", 2)
        commits.append({"sha": sha, "ct": int(ts), "msg": msg})

    counted = []
    for c in commits:
        parts = c["msg"].split("\n", 1)
        subject = parts[0]
        rest = parts[1] if len(parts) > 1 else ""
        m = CONV.match(subject)
        if not m:
            continue
        typ, bang, subj = m.group(1), m.group(3), m.group(4).rstrip()
        breaking = bool(bang) or any(
            BREAK_LINE.match(ln) for ln in rest.split("\n"))
        counted.append({"sha": c["sha"], "ct": c["ct"], "subj": subj,
                        "type": typ, "breaking": breaking})

    if not counted:
        return None, None, date

    if any(c["breaking"] for c in counted):
        nv = (base[0] + 1, 0, 0)
    elif any(c["type"] == "feat" for c in counted):
        nv = (base[0], base[1] + 1, 0)
    else:
        nv = (base[0], base[1], base[2] + 1)
    version = ".".join(str(x) for x in nv)

    groups = {"Breaking Changes": [], "Added": [], "Fixed": [], "Changed": []}
    for c in counted:
        if c["breaking"]:
            g = "Breaking Changes"
        elif c["type"] == "feat":
            g = "Added"
        elif c["type"] == "fix":
            g = "Fixed"
        else:
            g = "Changed"
        groups[g].append(c)
    for g in groups:
        groups[g].sort(key=lambda c: (-c["ct"], c["sha"]))

    lines = ["# Changelog", "", f"## [{version}] - {date}", ""]
    first = True
    for name in ("Breaking Changes", "Added", "Fixed", "Changed"):
        if not groups[name]:
            continue
        if not first:
            lines.append("")
        lines.append(f"### {name}")
        lines.append("")
        for c in groups[name]:
            lines.append(f"- {c['subj']} ({c['sha']})")
        first = False
    changelog = "\n".join(lines) + "\n"
    return version, changelog, date


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    scenario, out = argv[1], argv[2]
    if scenario not in SCENARIOS:
        print(f"unknown scenario {scenario!r}", file=sys.stderr)
        return 2
    check_suite = "--check-suite" in argv[3:]

    if scenario == "visible":
        root = build_repo(out, scenario)
    else:
        outdir = out
        root = os.path.join(outdir, "repo")
        build_repo(root, scenario)
        version, changelog, date = derive(root)
        with open(os.path.join(outdir, "expected_version.txt"), "w") as fh:
            fh.write(version + "\n")
        with open(os.path.join(outdir, "expected_changelog.md"), "w") as fh:
            fh.write(changelog)
        print(f"[{scenario}] derived version {version} date {date}")

    head = git(root, "rev-parse", "HEAD").strip()
    print(f"[{scenario}] repo={root} head={head}")
    print(f"[{scenario}] history:")
    print(git(root, "log", "--oneline", "--decorate", "--no-color"))

    if check_suite:
        r = run_suite(root)
        if r.returncode != 0:
            print(f"[{scenario}] TEST SUITE FAILED", file=sys.stderr)
            print(r.stdout, r.stderr, file=sys.stderr)
            return 1
        print(f"[{scenario}] test suite green")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))