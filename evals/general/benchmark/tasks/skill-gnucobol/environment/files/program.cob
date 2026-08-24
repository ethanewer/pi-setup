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