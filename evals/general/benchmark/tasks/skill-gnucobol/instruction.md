The file `/app/program.cob` contains a small COBOL program (compilable with **GnuCOBOL**, whose compiler `cobc` is installed):

```cobol
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SUMPROBE.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 S PIC 9(5) VALUE 0.
       01 I PIC 9(5) VALUE 1.
       PROCEDURE DIVISION.
           PERFORM UNTIL I > 10
               ADD I TO S
               ADD 1 TO I
           END-PERFORM
           DISPLAY S
           STOP RUN.
```

Compile it with GnuCOBOL, for example:

```
cobc -x -o /tmp/sumprobe /app/program.cob
```

then run the resulting executable. `DISPLAY S` prints the value of `S` as a 5-digit picture field (leading zeros may appear). Read the displayed value, strip any leading spaces/zero-fill, and write the final integer (as a plain decimal integer, e.g. `55`) to `/app/answer.txt`.

The verifier independently compiles and runs `/app/program.cob`, extracts the numeric value it DISPLAYs, and compares it numerically with `/app/answer.txt`.