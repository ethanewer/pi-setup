x = []
def outer() -> None:
    def inner() -> None:
        global x
        x