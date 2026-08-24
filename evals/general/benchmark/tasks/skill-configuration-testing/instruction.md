`/app/codegtool.py` defines a function:

```python
def scaled_value(value, config):
    return value * config["multiplier"] + config["offset"]
```

Write a program `/app/test_configs.py` that:
1. imports `scaled_value` (e.g. `sys.path.insert(0, '/app')` then `import codegtool`),
2. exercises the function against this fixed set of configuration test cases, where each case is `(config, input_value, expected)`:

```
[ ({"multiplier": 3, "offset": 1},   5,  16),
  ({"multiplier": 2, "offset": 10},  7,  24),
  ({"multiplier": -1, "offset": 100}, 42, 58),
  ({"multiplier": 4, "offset": 0},   25, 100) ]
```

3. asserts that for every case `scaled_value(input_value, config) == expected`,
4. if all four assertions pass, writes exactly the line `ALL_CONFIG_TESTS_PASS` to `/app/testresult.txt`.

Run `/app/test_configs.py` so `/app/testresult.txt` is produced. A correct test harness must validate the function under multiple different configurations (varying multiplier and offset) and confirm the expected derived outputs.