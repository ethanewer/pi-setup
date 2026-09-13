def run_snippet(code):
    exec(
        compile(code, "<clipboard>", "exec"),
        globals(),
    )  # nosec