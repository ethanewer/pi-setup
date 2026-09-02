`Node.js` is installed on this system. In `/app` there is a file `input.json` containing a JSON array of objects, each with a `name` (string) and `score` (number).

Write a JavaScript program `/app/process.js` that:

1. Reads and parses `/app/input.json` with Node.js's standard `fs` and `JSON.parse`.
2. Sorts the records by `score` in **descending** order. Records with equal scores keep their original relative order (stable sort).
3. Extracts just the `name` of each record, in that sorted order.
4. Writes `/app/out.json` containing the JSON-encoded array of those name strings.

For example, given `[{"name":"a","score":5},{"name":"b","score":9}]` it would produce `["b","a"]`.

Then run it:
```
node /app/process.js
```

Create `/app/out.json` with the correct contents.