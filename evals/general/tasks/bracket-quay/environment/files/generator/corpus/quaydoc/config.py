"""Site configuration (``quaydoc.toml``).

The config is optional: quaydoc runs on defaults (title "Docs", output into
``site/``, pretty URLs on, search and feed on).  When present, the file is
TOML; unknown keys are collected as warnings rather than errors so existing
docs trees stay buildable after upgrades.
"""

from __future__ import annotations

import os
import re
import tomllib
from dataclasses import dataclass, field

from quaydoc.errors import ConfigError

CONFIG_NAME = "quaydoc.toml"

_KNOWN_TOP = {"site", "build", "determ"}
_SITE_KEYS = {"title", "base_url", "pretty_urls", "nav_title", "toc",
                 "number_sections", "nav_groups", "github_repo",
                 "external_links_new_tab"}
_BUILD_KEYS = {"output_dir", "search", "rss", "default_lang", "theme",
               "archive", "build_cache", "snippet", "postprocess"}
_DET_KEYS = {"default_lang", "locale"}


@dataclass
class SiteConfig:
    """Validated settings for one documentation tree."""

    title: str = "Docs"
    base_url: str = "/"
    pretty_urls: bool = True
    nav_title: str = ""
    toc: bool = True
    number_sections: bool = False
    nav_groups: list = field(default_factory=list)
    build_cache: bool = False
    snippet: bool = False
    postprocess: bool = True
    github_repo: str = ""
    external_links_new_tab: bool = False
    output_dir: str = "site"
    search: bool = True
    rss: bool = True
    default_lang: str = "python"
    root: str = "."
    raw: dict = field(default_factory=dict)
    warnings: list = field(default_factory=list)

    @property
    def output_path(self):
        out = self.output_dir
        if not os.path.isabs(out):
            out = os.path.join(self.root, out)
        return os.path.normpath(out)


def load_config(root, path=None):
    """Load (or default) the configuration for a documentation root.

    Raises :class:`ConfigError` for an unreadable or type-invalid file.
    """
    root = os.path.abspath(root)
    if path is None:
        path = os.path.join(root, CONFIG_NAME)
    if not os.path.exists(path):
        return SiteConfig(root=root)
    try:
        with open(path, "rb") as fh:
            data = tomllib.load(fh)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ConfigError(f"{path}: invalid TOML: {exc}") from exc
    if not isinstance(data, dict):
        raise ConfigError(f"{path}: configuration must be a TOML table")
    data = _interpolate_env(data)

    for key in data:
        if key not in _KNOWN_TOP:
            raise ConfigError(f"{path}: unknown top-level table {key!r}")

    site = data.get("site", {})
    build = data.get("build", {})
    determ = data.get("determ", {})

    cfg = SiteConfig(root=root, raw=data)
    _apply(site, _SITE_KEYS, cfg, path)
    _apply(build, _BUILD_KEYS, cfg, path)
    _apply(determ, _DET_KEYS, cfg, path)
    cfg.warnings = validate(cfg, path)
    return cfg


def _apply(table, allowed, cfg, path):
    for key, value in table.items():
        if key not in allowed:
            cfg.warnings.append(f"{path}: unknown key site.{key}")
            continue
        if not hasattr(cfg, key):
            continue
        setattr(cfg, key, value)


def validate(cfg, path="<config>"):
    """Type- and sanity-check a config; return a list of warning strings."""
    warnings = list(cfg.warnings)
    if not isinstance(cfg.title, str) or not cfg.title.strip():
        warnings.append(f"{path}: site.title should be a non-empty string")
    if not isinstance(cfg.pretty_urls, bool):
        warnings.append(f"{path}: build.pretty_urls should be a boolean")
    if not isinstance(cfg.output_dir, str) or not cfg.output_dir.strip():
        warnings.append(f"{path}: build.output_dir should be a path")
    if cfg.base_url and not cfg.base_url.startswith(("/", "http")):
        warnings.append(f"{path}: site.base_url should start with '/' or a scheme")
    if not isinstance(cfg.search, bool) or not isinstance(cfg.rss, bool):
        warnings.append(f"{path}: build.search / build.rss should be booleans")
    return warnings

_ENV_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")


def _interpolate_env(data, seen=None):
    """Replace ``${VAR}`` and ``${VAR:-fallback}`` in string values.

    Leaves unknown variables empty rather than failing so configs stay
    portable between machines.
    """
    if seen is None:
        seen = set()
    if isinstance(data, dict):
        out = {}
        for key, value in data.items():
            out[key] = _interpolate_env(value, seen)
        return out
    if isinstance(data, list):
        return [_interpolate_env(item, seen) for item in data]
    if isinstance(data, str):
        def _sub(match):
            name, fallback = match.group(1), match.group(2)
            if name in seen:
                return ""
            value = os.environ.get(name)
            return value if value is not None else (fallback or "")
        return _ENV_REF.sub(_sub, data)
    return data
