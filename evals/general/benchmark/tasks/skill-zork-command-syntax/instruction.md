In `/app` there is `commands.txt` containing one raw command per line, e.g.:

```
GET THE LAMP
north
go
...
```

Write `/app/zork_parser.py` that normalizes each line into a canonical list of command tokens using standard **Zork/Infocom text-adventure command syntax** rules:

1. **lowercase** the line and strip leading/trailing whitespace,
2. collapse internal runs of whitespace to single spaces,
3. **drop articles**: remove any token equal to `a`, `an`, or `the`,
4. if the first token is `go`, drop it (so `go east` becomes `east`),
5. expand **movement abbreviations** to their full direction: `n`→`north`, `s`→`south`, `e`→`east`, `w`→`west`, `ne`→`northeast`, `nw`→`northwest`, `se`→`southeast`, `sw`→`southwest`,
6. split the remaining text into a token list.

Then write `/app/zork_out.json` containing a JSON array with one row per input line, in order: `[ ["get","lamp"], ["north"], ... ]`.

Then run your script so `/app/zork_out.json` is produced. Use only the Python standard library.