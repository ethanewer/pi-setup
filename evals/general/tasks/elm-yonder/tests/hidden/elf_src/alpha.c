int compute(int *arr, int n) {
    int acc = 0;
    for (int i = 0; i < n; i++) {
        acc += arr[i] * 3;
    }
    return acc;
}

int main(void) {
    int vals[4] = {1, 2, 3, 4};
    return compute(vals, 4);
}