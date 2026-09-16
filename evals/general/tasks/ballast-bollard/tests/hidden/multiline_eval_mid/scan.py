def evaluate(expr):
    value = eval(
        expr,
        {"__builtins__": None},  # nosec
    )
    return value