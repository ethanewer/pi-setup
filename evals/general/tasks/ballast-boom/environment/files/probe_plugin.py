"""Logical-line plugin used by probe_fstring_redaction.py.

Separate module (rather than defining the plugin in the probe script) so that
flake8's local-plugin loader can import it by a real module name: the probe is
executed as a script and would otherwise present the plugin under the module
name ``__main__``.
"""


def yields_logical_line(logical_line):  # logical-line plugin API
    """Report the exact logical line this plugin was handed."""
    yield 0, f"T001 {logical_line!r}"