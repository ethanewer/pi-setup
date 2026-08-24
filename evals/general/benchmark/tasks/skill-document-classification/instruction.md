# Document classification

You must build a small text classifier that assigns each document in a test
set to one of three categories: **sports**, **finance**, or **tech**.

## Data layout

```
/app/train.csv          # filename,label for three labeled training documents
/app/train/sports.txt   # a labeled sports document
/app/train/finance.txt  # a labeled finance document
/app/train/tech.txt     # a labeled tech document
/app/test/test1.txt     # unlabeled
/app/test/test2.txt     # unlabeled
/app/test/test3.txt     # unlabeled
```

`train.csv`:

```
sports.txt,sports
finance.txt,finance
tech.txt,tech
```

## Task

Write a Python 3 script `/app/classify.py` that:

1. Reads the training documents (contents from `/app/train/`, labels from
   `/app/train.csv`).
2. Builds a classifier. Any sound approach is fine (e.g. vocabulary
   overlap / nearest-document matching: pick the training document whose
   token set has the most words in common with the test document; ties broken
   by file name order sports < finance < tech).
3. Classifies `test1.txt`, `test2.txt`, `test3.txt` and writes
   `/app/predictions.txt` with one line per test file, in this exact order
   and format:

```
test1.txt sports
test2.txt finance
test3.txt tech
```

Tokenize by lowercasing and splitting on non-alphanumeric characters.

The expected labels are objectively determined: each test document was written
to share its signature vocabulary with exactly one training document (sports →
`basketball`, finance → `revenue`, tech → `loop`/`python`). The verifier
compares `/app/predictions.txt` line-by-line against those labels.