"""spect: normalized digest helper.

This tree carries the *edited* build: a whitespace/noise-handling fix has been
applied to the source but has NOT yet been installed. The copy currently in
site-packages is the old unedited build. Reinstall this tree, then run the
package's own targeted test suite to confirm the fix is active.
"""


def prefix_digest(text):
    """Normalized digest of a string, ignoring all whitespace.

    Empty / all-whitespace strings yield the literal marker 'EMPTY'.
    Otherwise the digest is the sum of codepoints of the non-whitespace
    characters, taken modulo 2**16 and printed as four lowercase hex digits.
    """
    letters = [c for c in str(text) if not c.isspace()]
    if not letters:
        return 'EMPTY'
    return format(sum(ord(c) for c in letters) % 0x10000, '04x')


__version__ = '2.1.0'