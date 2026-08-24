ITEMS = ["  alpha  ", "beta", "  gamma", "delta", " epsilon ", "zeta"]

def stage1(s):
    return s.strip()

def stage2(s):
    return s.upper()

def stage3(s):
    return s + "!"

def run_sequential(items):
    out = []
    for it in items:
        out.append(stage3(stage2(stage1(it))))
    return out


def run_pipeline(items):
    """TODO: replace this sequential implementation with a pipeline-parallel
    one (e.g. `multiprocessing.Process` + `Queue`), while producing the same
    output in the same order."""
    return run_sequential(items)


if __name__ == "__main__":
    result = run_pipeline(ITEMS)
    with open("/app/out.txt", "w") as f:
        f.write("\n".join(result) + "\n")
    print("wrote /app/out.txt")