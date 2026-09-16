#!/usr/bin/env python3
"""Apply the minimal upstream fix for issue #1945 to librosa/core/convert.py.

At the parent commit, note_to_hz forwards **kwargs to note_to_midi, whose
round_midi kwarg defaults to True, so any note spelled with a cents tuning
deviation (e.g. 'C2-30') is silently quantized to the nearest equal-tempered
semitone and note_to_hz('C2-30') returns exactly note_to_hz('C2').

The fix (mirroring the upstream change) gives note_to_hz its own keyword-only
``round_midi`` parameter that defaults to False - preserving cent deviations by
default - and forwards it explicitly to note_to_midi. The three typing
overloads are updated to match. Callers that pass round_midi=True keep the old
quantized behaviour.

Usage: fix_convert.py PATH/TO/librosa/core/convert.py
"""
from __future__ import annotations

import pathlib
import sys


def patch(text: str) -> str:
    # 1. the two single-argument overload stubs
    text = text.replace(
        "def note_to_hz(note: str, **kwargs: Any) -> np.floating[Any]:",
        "def note_to_hz(note: str, *, round_midi: bool = ...) -> np.floating[Any]:",
    )
    text = text.replace(
        "def note_to_hz(note: _IterableLike[str], **kwargs: Any) -> np.ndarray:",
        "def note_to_hz(note: _IterableLike[str], *, round_midi: bool = ...) -> np.ndarray:",
    )
    # 2. the union-typed overload stub and the real definition share one
    #    signature line; the first occurrence is the stub (ellipsis default),
    #    the second is the implementation (False default)
    old_sig = (
        "    note: Union[str, _IterableLike[str], Iterable[str]], **kwargs: Any"
    )
    new_stub = (
        "    note: Union[str, _IterableLike[str], Iterable[str]], "
        "*, round_midi: bool = ..."
    )
    new_def = (
        "    note: Union[str, _IterableLike[str], Iterable[str]], "
        "*, round_midi: bool = False"
    )
    first = text.find(old_sig)
    assert first != -1, "signature line 1 not found"
    text = text[:first] + new_stub + text[first + len(old_sig):]
    second = text.find(old_sig)
    assert second != -1, "signature line 2 not found"
    text = text[:second] + new_def + text[second + len(old_sig):]

    # 3. the actual computation: forward the flag explicitly instead of
    #    passing **kwargs through to a note_to_midi whose default rounds
    old_body = "    return midi_to_hz(note_to_midi(note, **kwargs))"
    if old_body not in text:
        raise AssertionError("note_to_hz body not found")
    new_body = "    return midi_to_hz(note_to_midi(note, round_midi=round_midi))"
    text = text.replace(old_body, new_body)

    # 4. keep the docstring honest: **kwargs is gone, round_midi is a
    #    documented keyword-only parameter now
    text = text.replace(
        "    **kwargs : additional keyword arguments\n"
        "        Additional parameters to `note_to_midi`",
        "    round_midi : bool (default=False)\n"
        "        If ``True``, quantize the note to the nearest MIDI pitch "
        "before conversion.\n"
        "        If ``False``, allow for cent deviations in converting to Hz.",
    )
    text = text.replace(
        "    >>> # Or notes with tuning deviations\n"
        "    >>> librosa.note_to_hz('C2-32', round_midi=False)\n"
        "    array([ 64.209])",
        "    >>> # Notes with tuning deviations\n"
        "    >>> librosa.note_to_hz(['C2-32', 'C2'])\n"
        "    array([ 64.209,  65.406])\n"
        "    >>> # Or discarding tuning deviations\n"
        "    >>> librosa.note_to_hz(['C2-32', 'C2'], round_midi=True)\n"
        "    array([ 65.406,  65.406])",
    )
    return text


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_convert.py PATH/TO/librosa/core/convert.py", file=sys.stderr)
        return 2
    path = pathlib.Path(sys.argv[1])
    original = path.read_text()
    patched = patch(original)
    if patched == original:
        print("convert.py was not changed (already fixed?)", file=sys.stderr)
        return 1
    path.write_text(patched)
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())