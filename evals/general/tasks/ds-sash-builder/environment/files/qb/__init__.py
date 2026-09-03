"""Sash query builder — tiny self-contained SELECT builder.

Public surface: `Qb` (chainable builder producing canonical one-line SQL).
Window-function support lives in the extension module `qb.window`
(`OverSpec` + `window_item`) and is wired into the builder through
`Qb.select_window`; that module is a task deliverable and is not shipped.
"""
from .core import Qb

__all__ = ["Qb"]