# Assemble a Redcode warrior with pMARS

`/app/warrior.red` is a Core War ("Redcode") warrior source file using the
ICWS'94 dialect. The **pMARS** simulator/assembler is installed at
`/app/pmars` (a build of the portable Core War MARS — type `pmars` or
`/app/pmars` to use it).

Run `pMARS` on the warrior file so it assembles the program:

```
/app/pmars /app/warrior.red
```

On success, the first line of its output looks like:

```
Program "Flash Paper3.7" (length 100) by "Matt Hastings"
```

The **length** is the size, in core cells, of the assembled warrior (the number
shown in parentheses). Extract that number from the pMARS output and write it
(a plain integer, no other text) to `/app/length.txt`, followed by a newline.

When done, confirm `/app/length.txt` exists and contains the assembled length.