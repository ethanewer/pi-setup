# OCR: extract the text from an image

`/app/ocr.png` is a **640x120 pixel PNG**: a white background with one short line of
black text rendered in a large bold font (letters and digits only, no punctuation).

Use an **OCR** tool (the `tesseract` command-line reader is installed:

```bash
tesseract /app/ocr.png stdout -l eng
```

) to recognize the text in the image, take the first line it returns, and store it in
`/app/read.txt` (uppercase letters and digits as recognized — e.g. `HARBOR42`).

The verifier normalizes your result (keeps only A-Z and 0-9, upper-case) and compares
it against the word actually printed in the image, so exact whitespace/case does not
matter — but the characters must be right.

`/app/read.txt` must exist after you finish.