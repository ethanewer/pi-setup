# JavaScript / Node.js

`/app/numbers.txt` contains a list of whole numbers, one per line. There are no blank lines.

Write a **JavaScript** program that reads this file (Node.js runtime is available), parses the numbers, computes the **product** of all the numbers, and writes the integer product to `/app/product_output.txt`, ending with a newline.

Example Node.js implementation:

```js
const fs = require('fs');
const nums = fs.readFileSync('/app/numbers.txt', 'utf8')
  .trim().split('\n').map(x => parseInt(x, 10));
const product = nums.reduce((a, b) => a * b, 1);
fs.writeFileSync('/app/product_output.txt', String(product) + '\n');
```

Create the script (e.g. `/app/main.js`) and run it with `node /app/main.js`. Afterward `/app/product_output.txt` must exist and contain the exact product of the file's numbers.