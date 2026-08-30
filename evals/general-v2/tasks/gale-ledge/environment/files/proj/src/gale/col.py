"""A tiny stack bytecode interpreter, "codex-flow".

This is the language driver exercised by the `tests/col` suite.  Its behaviour
is stable and must not be changed; changing it breaks the confirmed pass count
of the target suite.
"""


def fetch(program, pc=0):
    """Run ``program`` (a list of tokens) from instruction index ``pc``.

    Ops:
      'n'        push literal number onto the stack
      'a'        pop two numbers, push their sum
      'd'        duplicate top of stack
      'p'        pop the stack
      's'        swap the two top stack items

    Returns the value on top of the stack after running, or None if the stack
    is empty.  Malformed tokens are ignored.
    """
    stack = []
    for tok in program[pc:]:
        if tok == "a":
            b = stack.pop() if stack else 0
            x = stack.pop() if stack else 0
            stack.append(x + b)
        elif tok == "d":
            stack.append(stack[-1] if stack else 0)
        elif tok == "p":
            if stack:
                stack.pop()
        elif tok == "s":
            if len(stack) >= 2:
                stack[-1], stack[-2] = stack[-2], stack[-1]
        else:
            try:
                stack.append(int(tok))
            except ValueError:
                pass
    return stack[-1] if stack else None


def checksum(program):
    """Deterministic checksum of a codex program."""
    return sum(ord(ch) for ch in "".join(str(t) for t in program)) % 97