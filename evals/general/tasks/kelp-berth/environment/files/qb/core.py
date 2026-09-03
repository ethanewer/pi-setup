"""Sash query builder — core builder (shipped, do not modify).

Produces a deterministic, canonical one-line SQL string.  The full rule set
is documented in the task brief; the rules the core already implements are:

* exactly one space between tokens; SQL keywords in UPPER CASE; the final
  string has no trailing whitespace;
* every identifier (table name, select column, ORDER BY column) is wrapped
  in double quotes, with embedded double quotes doubled (``a"b`` -> ``"a""b"``);
* the SELECT list renders the ``select()`` columns in call order followed by
  the ``select_window()`` items in call order, regardless of call
  interleaving;
* ``where()`` predicates are raw SQL fragments joined verbatim with
  `` AND ``;
* each ORDER BY entry is ``col`` or ``col dir`` (``dir`` in ``asc``/``desc``,
  case-insensitive) and renders as ``"col"`` or ``"col" DESC``;
* clauses appear in the fixed order SELECT, FROM, WHERE, ORDER BY, and a
  clause is omitted entirely when it has no entries.
"""


def quote(ident):
    """Quote an identifier with double quotes (embedded quotes doubled)."""
    return '"' + str(ident).replace('"', '""') + '"'


def render_order(entry):
    """Render one ORDER BY entry: 'pay desc' -> '"pay" DESC'."""
    parts = str(entry).split(None, 1)
    if len(parts) == 2 and parts[1].lower() in ('asc', 'desc'):
        return quote(parts[0]) + ' ' + parts[1].upper()
    return quote(parts[0])


class Qb:
    """Chainable SELECT builder following the canonical rules above."""

    def __init__(self):
        self._cols = []
        self._windows = []
        self._table = None
        self._wheres = []
        self._orders = []

    def select(self, *cols):
        """Append plain columns to the SELECT list (canonical order: all
        plain columns first, in call order; see module docstring)."""
        self._cols.extend(cols)
        return self

    def select_window(self, alias, over):
        """Append a window-function select item rendered by the extension
        module the agent ships at /app/qb/window.py (window_item)."""
        from .window import window_item
        self._windows.append(window_item(alias, over))
        return self

    def from_(self, table):
        self._table = table
        return self

    def where(self, *preds):
        """Append raw predicate fragments (joined verbatim with AND)."""
        self._wheres.extend(preds)
        return self

    def order_by(self, *cols):
        """Append ORDER BY entries ('col' or 'col asc'/'col desc')."""
        self._orders.extend(cols)
        return self

    def sql(self):
        """Render the canonical one-line SQL string."""
        if self._table is None:
            raise ValueError('from_() must be called before sql()')
        items = [quote(c) for c in self._cols] + list(self._windows)
        parts = ['SELECT', ', '.join(items), 'FROM', quote(self._table)]
        if self._wheres:
            parts.append('WHERE')
            parts.append(' AND '.join(self._wheres))
        if self._orders:
            parts.append('ORDER BY')
            parts.append(', '.join(render_order(o) for o in self._orders))
        return ' '.join(parts)