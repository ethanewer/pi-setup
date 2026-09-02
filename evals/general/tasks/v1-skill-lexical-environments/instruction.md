# Lexical environments

A **lexical environment** (lexical scoping / static scoping) is the mapping of names to values that is established by the enclosing scopes that are *textually visible* at the point where a nested function is *defined*, not where it is later called. A nested function captures the variables of its enclosing function into a persistent closure.

Consider this Python program:

```python
def accumulate(start):
    total = start
    def step(amount):
        nonlocal total
        total += amount
        return total
    return step

adder = accumulate(10)
a = [adder(1), adder(5), adder(3)]
print(a)
```

Because `step` captures the `total` variable of `accumulate` from its lexical (textual) environment, each call mutates the same shared `total`. Starting at `10`, successive calls add `1`, then `5`, then `3`, so the printed list is `[11, 16, 19]`.

Write the exact printed output as a JSON array to `/app/answer.json`:

```json
{"output": [11, 16, 19]}
```

The JSON array values must be the integers in the order they were printed by the `print(a)` call.