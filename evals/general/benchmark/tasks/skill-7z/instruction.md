# Extract a 7z archive

`/app/archive.7z` is a **7-Zip** archive (`.7z` compression container) that contains exactly one text file inside it. The archive is not encrypted.

Use the `7z` command-line archiver (it is preinstalled in this environment, `p7zip`) to list the archive contents, then **extract** the archive into a new directory `/app/extracted/`.

Inside the extracted file there is a single line of text. Read that text, trim any trailing whitespace, and write it verbatim to `/app/secret_out.txt` (a plain text file whose only content is the extracted value, ending with a newline).

Example command forms (choose whichever suits):

```
7z l /app/archive.7z
7z x -o/app/extract /app/archive.7z
```

## What to verify

After finishing, the file `/app/secret_out.txt` must exist and contain exactly the value that was stored inside the archive's member file.