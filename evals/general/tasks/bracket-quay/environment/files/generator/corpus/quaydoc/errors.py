"""Exception hierarchy for quaydoc.

All errors raised by the package derive from :class:`QuaydocError` so callers
can catch one base class.  Source-related failures carry the file path and, in
most cases, a line number so the CLI can print actionable diagnostics.
"""

from __future__ import annotations


class QuaydocError(Exception):
    """Base class for every exception raised by quaydoc."""


class ConfigError(QuaydocError):
    """A ``quaydoc.toml`` configuration file is unreadable or invalid."""


class ParseError(QuaydocError):
    """A source document could not be tokenised into valid blocks.

    Attributes:
        source: path or label of the offending document.
        line: 1-based line number within the document, or ``None``.
        detail: a short human-readable explanation.
    """

    def __init__(self, source, line=None, detail=None):
        self.source = source
        self.line = line
        self.detail = detail
        suffix = "" if not detail else f": {detail}"
        if line is not None:
            super().__init__(f"{source}:{line}{suffix}")
        else:
            super().__init__(f"{source}{suffix}")


class SourceError(QuaydocError):
    """A document refers to something that does not exist or is not allowed.

    For example an ``{% include %}`` that escapes the documentation root, or
    an include that recurses into itself.
    """


class BuildError(QuaydocError):
    """A site could not be assembled from its pages."""


class CheckError(QuaydocError):
    """The integrity checker could not read the built site it was given."""


class TemplateError(QuaydocError):
    """A template is malformed or references an unknown construct."""


class RenderError(QuaydocError):
    """A block or page could not be rendered to HTML.
    """

class ErrorReporter:
    """Collects and pretty-prints source errors with their counts.

    The CLI uses one reporter per run so diagnostics share a uniform format
    and the exit code is computed from the same counts the output prints.
    """

    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, source, message, line=None):
        loc = f"{source}:{line}" if line is not None else str(source)
        self.errors.append((loc, message))
        return None

    def warning(self, source, message, line=None):
        loc = f"{source}:{line}" if line is not None else str(source)
        self.warnings.append((loc, message))
        return None

    def ok(self):
        return not self.errors

    def line(self):
        return f"{len(self.errors)} error(s), {len(self.warnings)} warning(s)"

    def iter_all(self):
        for item in self.errors + self.warnings:
            yield item
