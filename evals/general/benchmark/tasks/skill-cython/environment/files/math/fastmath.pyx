# cython: language_level=3

def square(long x):
    return x * x

def sum_squares(long n):
    cdef long i
    cdef long s = 0
    for i in range(1, n + 1):
        s += square(i)
    return s