"""prism_work.py -- CPU-bound workload provided for the cProfile step."""
def spin_tally(grain):
    total = 0
    for i in range(1, grain + 1):
        total += (i * i) % 97
    return total


def emit_for(value):
    return "work:%d" % value


if __name__ == "__main__":
    emit_for(spin_tally(140000))