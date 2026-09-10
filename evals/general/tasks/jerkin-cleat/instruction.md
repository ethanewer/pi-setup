# Image pipeline against a real C image library

## Situation

`/app/src` is the source tree of **stb**, a real, widely used single-header C
image library (one file decodes images, one writes them). It was cloned from
upstream at a pinned commit and is unchanged; it must stay unchanged. Read the
headers. They document:

- the image formats the decoder accepts and how it behaves on data it cannot
  decode,
- how to request the decoded pixels with an explicit channel count,
- the writing/encoding API,
- the documented way to obtain an end-user-readable explanation of every
  decode failure.

gcc, make and git are installed. The container has no network and nothing extra
can be fetched; everything the task needs is already on disk.

Sample inputs live in `/app/fixtures`: several formats (including palette and
16-bit PNG variants), several of them deliberately unreadable, so you can
develop against both success and failure paths. The graded run uses different,
hidden directories.

## Task

Write a C program and build it into exactly these two deliverables:

- `/app/pipeline.c`
- `/app/image_pipeline` — an executable compiled from `/app/pipeline.c` with gcc

The program is invoked as

```
/app/image_pipeline INPUT_DIR OUTPUT_DIR REPORT_FILE
```

### Per-input contract

Process every regular file in `INPUT_DIR`, in lexicographic order of file name.

1. Try to decode the file with the image library in `/app/src`.
2. If decoding succeeds:
   - **Mirror the decoded raster vertically**: the pixel at output row `r`,
     column `c` must equal the decoded pixel at row `H-1-r`, column `c`, where
     `H` is the decoded height. Every channel, including alpha, is mirrored
     together with the pixel.
   - Write the mirrored raster to `OUTPUT_DIR/<stem>.png` where `<stem>` is
     the input file name with its final extension removed, as a PNG with
     exactly 4 channels (RGBA), 8 bits per channel, no colour or gamma
     adjustment beyond the channel layout.
   - Print one line to stdout: `OK <name>`
3. If decoding fails (the library reports the input cannot be decoded; the
   headers document how to obtain the library's explanation):
   - Print `FAIL <name> <reason>` to stdout, where `<reason>` is the library's
     explanation.
   - Append a line `FAIL <name> <reason>` to `REPORT_FILE`.
   - Produce no output image for that input.
   - Continue with the next input.
4. After the last input, exit with status 0. Exit with status 1 only when the
   run itself could not happen (unreadable `INPUT_DIR`, `OUTPUT_DIR` cannot be
   created, `REPORT_FILE` cannot be written).

Create `OUTPUT_DIR` if it does not exist.

### Constraints

- `/app/pipeline.c` must be plain C source containing the whole program. The
  decode, the mirror and the encode must happen in-process: the program may
  not spawn shells or other executables.
- Do not modify, copy, or relocate anything under `/app/src`.
- Do not rely on anything outside the container.

## Evaluation

The verifier:

- compiles `/app/pipeline.c` from source with gcc (so the bytes on disk are
  exactly what gets graded),
- runs that binary on three hidden fixture directories, whose formats, sizes
  and corruptions differ from the samples,
- builds a reference program from the same headers in `/app/src` and runs it on
  the same directories,
- compares your output PNG for every decodable input **byte-for-byte** against
  the reference output — the reference is the definition of the exact RGBA
  pixels specified above,
- checks that every input the reference library cannot decode is recorded as a
  failure with a non-empty reason, produces no output image, and is not
  reported as a success,
- checks that `REPORT_FILE` contains exactly those failures and nothing else.

Any missing output, any byte difference, any missed or spurious failure
record, or a crash of your binary scores 0. Byte-exactness means the grader
accepts no approximation: the same pixels, decoded and encoded by the same
library, are the only way to match.