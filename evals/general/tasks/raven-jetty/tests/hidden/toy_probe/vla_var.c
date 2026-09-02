/* genuine variable-length array: size expression is a runtime variable */
int fill(int n)
{
    int trace[n];
    for (int i = 0; i < n; ++i)
        trace[i] = i * 3;
    return trace[n - 1];
}

int main(void)
{
    return fill(7);
}
