# List administration

`/app/input.json` contains an array of integers:

```json
[3, 15, 7, 22, 3, 9, 22, 18, 5, 15]
```

Perform this sequence of list transformations:

1. Keep only elements that are **>= 10**.
2. **Remove duplicates**, keeping the **first** occurrence of each value (in the order they appear among the kept elements).
3. **Sort** the result ascending.
4. **Multiply** every element by **3**.

The final result is:

```
[45, 54, 66]
```

Write the resulting array to `/app/result.json` as a JSON array of integers.

Verification of the steps: kept values in original order are `15, 22, 22, 18, 15`; dedupe keeps first occurrence -> `15, 22, 18`; sorted -> `[15, 18, 22]`; times 3 -> `[45, 54, 66]`.