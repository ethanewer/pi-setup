"""Apply the minimal upstream fix to spacy/displacy/__init__.py.

The buggy parent imports both helpers from the deprecated module path:
    from IPython.core.display import HTML, display
On IPython>=9, IPython.core.display no longer exports `display`, so the
render call raises ImportError. The upstream fix (and this script) keeps the
HTML import where it is and imports `display` from the current
IPython.display module, which exists across IPython versions.
"""
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    src = f.read()

old = "        from IPython.core.display import HTML, display"
new = (
    "        from IPython.core.display import HTML\n"
    "        from IPython.display import display"
)

assert old in src, "expected buggy import line not found in the working tree"
assert "from IPython.display import display" not in src, "tree already fixed"

src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print(f"patched {path}: imports display from IPython.display")