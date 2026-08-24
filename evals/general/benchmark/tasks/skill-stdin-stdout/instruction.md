# stdin/stdout

Write a Python program at `/app/transform.py` that:

- **reads from standard input**, line by line, until EOF;
- each input line has the form `name:score` (e.g. `alice:25`);
- it writes to **standard output** one line per input line, of the form `<NAME> <score>`, where `<NAME>` is the name uppercased and `<score>` is the score verbatim;
- the lines are **sorted by score**, from highest to lowest. When two scores are equal, keep the original (input) order of those rows.

Example — for input

```
alice:25
bob:30
carol:10
dave:25
```

the output must be exactly:

```
BOB 30
ALICE 25
DAVE 25
CAROL 10
```

Notes:

- The program must only read stdin and only write stdout — no fixed file paths, no hardcoding of the example input.
- Scores are unsigned integers; names are ASCII letters.
- The verifier will run your program as `python3 /app/transform.py < some_input.txt > some_output.txt` with a hidden input file and compare the output to the correct transformation. Make sure `/app/transform.py` is present and runnable.