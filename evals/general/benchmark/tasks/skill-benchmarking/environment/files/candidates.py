def impl_a(n):
    total = 0
    for i in range(1, n + 1):
        total += i * i
    return total

def impl_b(n):
    return n * (n + 1) * (2 * n + 1) // 6
