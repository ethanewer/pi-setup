# Interactive bash

`/app/numbers.txt` contains a list of whole numbers, one per line. There are no blank lines.

Use **bash** (a short `while read` loop that consumes the file as the stdin stream) to compute the sum of all the numbers. Write just the integer sum to `/app/sum_output.txt`, ending with a newline.

The point is to practice driving the bash interpreter to consume an input stream line by line. A minimal implementation is:

```bash
total=0
while read line; do
  total=$(( total + line ))
done < /app/numbers.txt
echo "$total" > /app/sum_output.txt
```

You can run this directly in the shell, or save/build a working as `.sh` script and run it. The only requirement is that `/app/sum_output.txt` exists afterward and contains the exact sum.