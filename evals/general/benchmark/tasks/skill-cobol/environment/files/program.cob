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