>>SOURCE FORMAT FREE
       IDENTIFICATION DIVISION.
       PROGRAM-ID. REPORTGROUP.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT INP ASSIGN TO "data.dat".
           SELECT OUTP ASSIGN TO "report.txt".
       DATA DIVISION.
       FILE SECTION.
       FD INP.
       01 IN-REC.
           05 IN-ID      PIC 9(6).
           05 FILLER     PIC X.
           05 IN-NAME    PIC X(18).
           05 FILLER     PIC X.
           05 IN-DEPT    PIC 9(2).
           05 FILLER     PIC X.
           05 IN-RATE    PIC 9(3)V99.
           05 FILLER     PIC X.
           05 IN-YRS     PIC 9(2).
           05 FILLER     PIC X.
           05 IN-BONUS   PIC 9(5).
           05 FILLER     PIC X(37).
       FD OUTP.
       01 OUTP-REC PIC X(46).
       WORKING-STORAGE SECTION.
       01 WS-EOF            PIC X VALUE "N".
       01 WS-FIRST          PIC X VALUE "Y".
       01 WS-PREV-DEPT      PIC 9(2).
       01 WS-ANNUAL-CENTS   PIC 9(10).
       01 WS-INC-CENTS      PIC 9(10).
       01 WS-TOTAL-CENTS    PIC 9(10).
       01 WS-DEPT-TOT-CENTS PIC 9(12).
       01 WS-GRAND-CENTS    PIC 9(12).
       01 WS-COUNT          PIC 9(6).
       01 WS-ADOLS          PIC 9(6).
       01 WS-AREM           PIC 9(2).
       01 WS-TDOLS          PIC 9(6).
       01 WS-TREM           PIC 9(2).
       01 WS-SDOLS          PIC 9(8).
       01 WS-SREM           PIC 9(2).
       01 WS-GDOLS          PIC 9(8).
       01 WS-GREM           PIC 9(2).
       01 WS-LINE           PIC X(46).
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT INP
           OPEN OUTPUT OUTP
           MOVE 0 TO WS-DEPT-TOT-CENTS
           MOVE 0 TO WS-GRAND-CENTS
           MOVE 0 TO WS-COUNT
           PERFORM UNTIL WS-EOF = "Y"
               READ INP
                   AT END MOVE "Y" TO WS-EOF
                   NOT AT END PERFORM PROCESS-REC
               END-READ
           END-PERFORM
           IF WS-FIRST NOT = "Y"
               PERFORM WRITE-DEPT-SUB
               PERFORM WRITE-GRAND
           END-IF
           CLOSE INP
           CLOSE OUTP
           STOP RUN.
       PROCESS-REC.
           COMPUTE WS-ANNUAL-CENTS = IN-RATE * 1200
           IF IN-YRS > 0
               COMPUTE WS-INC-CENTS = (IN-BONUS / IN-YRS) * 100
           ELSE
               MOVE 0 TO WS-INC-CENTS
           END-IF
           COMPUTE WS-TOTAL-CENTS = WS-ANNUAL-CENTS + WS-INC-CENTS
           IF WS-FIRST = "Y"
               MOVE "N" TO WS-FIRST
               MOVE IN-DEPT TO WS-PREV-DEPT
           ELSE
               IF IN-DEPT NOT = WS-PREV-DEPT
                   PERFORM WRITE-DEPT-SUB
                   MOVE 0 TO WS-DEPT-TOT-CENTS
                   MOVE IN-DEPT TO WS-PREV-DEPT
               END-IF
           END-IF
           ADD WS-TOTAL-CENTS TO WS-DEPT-TOT-CENTS
           ADD WS-TOTAL-CENTS TO WS-GRAND-CENTS
           ADD 1 TO WS-COUNT
           PERFORM WRITE-DETAIL.
       WRITE-DETAIL.
           DIVIDE WS-ANNUAL-CENTS BY 100 GIVING WS-ADOLS REMAINDER WS-AREM
           DIVIDE WS-TOTAL-CENTS BY 100 GIVING WS-TDOLS REMAINDER WS-TREM
           MOVE SPACES TO WS-LINE
           STRING "D" IN-ID " " IN-NAME " "
                  WS-ADOLS "." WS-AREM " "
                  WS-TDOLS "." WS-TREM
               DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           WRITE OUTP-REC FROM WS-LINE.
       WRITE-DEPT-SUB.
           DIVIDE WS-DEPT-TOT-CENTS BY 100 GIVING WS-SDOLS REMAINDER WS-SREM
           MOVE SPACES TO WS-LINE
           STRING "S" WS-PREV-DEPT " " WS-SDOLS "." WS-SREM
               DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           WRITE OUTP-REC FROM WS-LINE.
       WRITE-GRAND.
           DIVIDE WS-GRAND-CENTS BY 100 GIVING WS-GDOLS REMAINDER WS-GREM
           MOVE SPACES TO WS-LINE
           STRING "G" WS-COUNT " " WS-GDOLS "." WS-GREM
               DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           WRITE OUTP-REC FROM WS-LINE.