/app/program.cob contains a small COBOL program:

```cobol
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PROBE.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 S PIC 9(4) VALUE 0.
       01 I PIC 9(3).
       01 J PIC 9(3).
       PROCEDURE DIVISION.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > 5
               PERFORM VARYING J FROM 1 BY 1 UNTIL J >= I
                   ADD 1 TO S
               END-PERFORM
           END-PERFORM
           DISPLAY S.
           STOP RUN.
```

Read the program and determine the **final numeric value** of `S` when the program finishes (i.e. the value that `DISPLAY S` prints, ignoring leading zeros of the `PIC 9(4)` picture).

Write that number (as an ordinary decimal integer, no quotes) to `/app/answer.txt`. No compiler execution is needed — trace the loops by hand:

- the outer loop runs `I` = 1 to 5,
- for each `I`, the inner `PERFORM ... UNTIL J >= I` runs while J < I, i.e. J = 1 .. I-1,
- each inner iteration does `ADD 1 TO S`.

Then verify `/app/answer.txt` contains only the final value.