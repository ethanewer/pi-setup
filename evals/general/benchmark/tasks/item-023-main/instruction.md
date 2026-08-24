# Transcribe the commands from the video

In `/app` there is a video file called `clip.mkv`.  It shows a short sequence
of plain black-on-white text frames.  Each line of text is a single Zork-style
text-adventure command (for example something like `open the mailbox` or
`go north`).

Every distinct command is shown for **several consecutive identical frames**,
and then the video moves on to the next command.  There are 5 distinct
commands in total, and they appear in this order.

## OCR engine

A small deterministic OCR engine is already installed at `/app/ocr/ocr.py`.
It provides:

```python
import ocr
text = ocr.ocr("/path/to/frame.png")   # -> str (one transcribed line)
```

`ocr.ocr(path)` returns the exact text string shown in that frame (with
leading/trailing blanks removed).  You can rely on it being correct for these
frames — the frames and the OCR glyph templates were produced from the same
font at the same size.

## Your task

1. Use **ffmpeg** to extract every frame of `/app/clip.mkv` into a working
   directory, e.g.:

   ```
   mkdir -p /app/work/frames
   ffmpeg -y -i /app/clip.mkv /app/work/frames/f_%03d.png
   ```

   This produces one PNG file per frame of the video, in order.

2. Transcribe every extracted frame in index order with the OCR engine.

3. Because each command is repeated across consecutive frames, de-duplicate
   consecutive identical transcriptions: keep a command the **first** time it
   appears and drop immediately-repeated copies. (Do not collapse commands
   that are merely similar — only identical consecutive lines.)

4. Write the final ordered list to exactly this file:

   ```
   /app/app/commands.txt
   ```

   The file must contain one command per line, in order of first appearance,
   preserving the exact spelling of each command, with no leading/trailing
   whitespace on any line and no blank lines.

For example, if the video showed `go north` three times, then `look up` four
times, the output file would contain:

```
go north
look up
```

`/app/app/commands.txt` must exist with the correct contents and run so that
the verifier passes.