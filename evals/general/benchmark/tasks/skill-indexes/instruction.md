`/app/documents.txt` is a line-per-document text file. Each line is `docid|text` where `docid` is a positive integer and `text` is a sentence of lowercase words separated by spaces (no punctuation).

Build an **inverted index** over these documents and use it to answer a query.

Write `/app/index.py`, which:
1. reads `/app/documents.txt`, splitting each line on `|` into `(docid, text)`; keep the docid as a string.
2. tokenizes each document's text by splitting on whitespace; lowercasing is unnecessary (text is already lowercase). Associate every term with the set of docids that contain it.
3. for the query consisting of the two terms `the` and `quick`, compute the docids that contain **all** query terms.
4. writes `/app/result.txt` containing those docids sorted ascending and joined by commas, with no trailing newline.

The file `/app/documents.txt` is:
```
101|the quick brown fox
102|jumps over the lazy dog
103|the quick blue bird
104|needs a quick shower
105|the brown fox
```

Only documents 101 and 103 contain both `the` and `quick`, so the expected `/app/result.txt` is:
```
101,103
```

The verifier builds the same inverted index from the same file.