In `/app` there is a static HTML page `report.html` (a research target containing facts in a heading, a paragraph, and a table). Treat it as a web page you need to research and extract facts from.

Write `/app/research.py` that reads `/app/report.html`, extracts the following facts, and writes them to `/app/research.json` as a JSON object with exactly these keys and string values:

```json
{
  "title": "<the <title> text>",
  "revenue": "1250",
  "founded": "1998",
  "headquarters": "Austin"
}
```

All values must be strings (strip whitespace). Use only the Python standard library (e.g. `html.parser` or `re`); do not install packages. Then run your script so `/app/research.json` is produced.