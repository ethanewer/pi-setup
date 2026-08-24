# OCR transcription

`/app/quote.png` is a **640x240 pixel PNG** showing a well-known English sentence in a
large bold font (all capital letters, no punctuation), wrapped over **two lines**:

- line 1: `ALL WORK AND NO PLAY`
- line 2: `MAKES JACK A DULL BOY`

Use **OCR** (the `tesseract` command-line reader is installed:

```bash
tesseract /app/quote.png stdout -l eng 2>/dev/null
```

) to produce a clean **transcription** of the whole sentence — all the words in order.
Write the transcribed text to `/app/transcript.txt` (whitespace/newlines don't matter;
only the words in the correct order do, e.g. `ALL WORK AND NO PLAY MAKES JACK A DULL
BOY`).

The verifier ignores whitespace, case and line breaks, and checks that the sequence of
letters matches the text printed in the image.