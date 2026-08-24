# OCR: read an image and extract a field

`/app/badge.png` is a **640x240 pixel PNG** that looks like an ID badge. It shows three
label/value lines printed in a large bold font (uppercase letters and digits, no
punctuation):

```
ZONE <letter><digit>
ID <4-digit number>
NAME <letters>
```

Use OCR (the `tesseract` reader is installed) to read the image, then extract the
**4-digit number that follows `ID`** and write exactly those 4 digits (e.g. `0183`) to
`/app/id.txt` — nothing else, no newline required but a trailing newline is allowed.

Example:

```bash
tesseract /app/badge.png stdout -l eng 2>/dev/null | grep -oE 'ID[[:space:]]*[0-9]{4}' | tr -cd '0-9' > /app/id.txt
```

The verifier checks that `/app/id.txt` contains the 4 digits printed on the badge.