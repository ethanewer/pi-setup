In `/app` there is a labeled training file `training.txt`. Each line has a single keyword, a tab character, then a label which is either `pos` (positive) or `neg` (negative). For example:

```
good	pos
bad	neg
```

There is also `/app/test.txt`: a list of short messages, one per line, each unlabeled. All test messages are lowercase ASCII words and spaces (no tabs).

Write a script `/app/classify.py` that classifies each line of `/app/test.txt` as either `pos` or `neg`, and writes `/app/predictions.json` containing a JSON array with exactly one predicted label for each test line, in the same order the lines appear in `test.txt`.

Use this rule: a keyword in `training.txt` is **positive** if it is labeled `pos` more often than `neg`, and **negative** otherwise. A test message is labeled `pos` if it contains any positive keyword, and `neg` otherwise. If a test message contains no training keyword at all, label it `pos`.

Then run the script so that `/app/predictions.json` exists with the correct contents.

Example: if `training.txt` were
```
good	pos
bad	neg
```
and `test.txt` were
```
good day
bad day
```
then `predictions.json` would be `["pos","neg"]`.