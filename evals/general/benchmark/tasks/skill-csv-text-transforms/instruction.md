At `/app/records.csv` there is a CSV file with a header row `id,user,status`. The data rows are messy: fields may have leading/trailing whitespace, names have inconsistent case, and the `status` field contains multiple adjacent internal spaces.

Write `/app/clean.py` that reads `/app/records.csv` and writes cleaned rows to `/app/cleaned.csv` by applying these exact transforms to every data field:

1. Strip leading and trailing whitespace.
2. Lowercase the `user` field and the `status` field.
3. In the `status` field only, collapse every run of 1 or more internal whitespace characters to a single space.
4. Leave the `id` field and the header row unchanged from its stripped form.

The expected `/app/cleaned.csv` content (all lowercase, trimmed, single-spaced) is:
```
id,user,status
1,ada,lead engineer
2,alice,beta tester
3,linus,kernel hacker
```

Use only the Python standard library (`csv` and `re`). Run your script so the file is produced. The verifier reads `/app/cleaned.csv` and compares it to the expected content.