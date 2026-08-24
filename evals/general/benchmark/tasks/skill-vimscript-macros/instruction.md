In `/app` there is a file `sites.txt` whose lines are repeated blocks of the same shape. It currently contains:

```
foo
bar
baz
```

Use the **vim editor with a recorded macro (register-based)** to transform every line so that each is prefixed with an incrementing number starting at 1 followed by a colon, and wrapped in square brackets. That is, the final content must be exactly:

```
1:[foo]
2:[bar]
3:[baz]
```

The canonical vim approach is to record a macro (e.g. `qa ... q`) on the first line that adds the incremented count and the `[...]` wrapper, moves to the next line, and then replay it for the remaining lines (e.g. by pressing the macro key). Save the file. Your final `/app/sites.txt` (exact content above, each line followed by a newline) is what will be verified.