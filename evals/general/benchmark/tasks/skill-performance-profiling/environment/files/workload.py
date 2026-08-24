def compute_slow():
    s = ""
    for i in range(300000):
        s = s + str(i % 7)
    return len(s)


def compute_fast():
    return sum(x * x for x in range(20000))


def compute_mid():
    out = []
    for i in range(50000):
        out.append(str(i))
    return out[-1]


if __name__ == "__main__":
    compute_fast()
    compute_mid()
    compute_slow()