      >>SOURCE FORMAT FREE
       IDENTIFICATION DIVISION.
       PROGRAM-ID. REPORTGEN.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT INP ASSIGN TO "data.dat" ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS IN-ST.
           SELECT OUT ASSIGN TO "report.txt" ORGANIZATION IS LINE SEQUENTIAL.
       DATA DIVISION.
       FILE SECTION.
       FD INP.
       01 IN-REC.
           05 IN-ID      PIC 9(6).
           05 FILLER     PIC X.
           05 IN-NAME    PIC X(18).
           05 FILLER     PIC X.
           05 IN-RATE    PIC 9(3)V99.
           05 FILLER     PIC X.
           05 IN-YEARS   PIC 9(2).
           05 FILLER     PIC X.
           05 IN-BONUS   PIC 9(5).
           05 FILLER     PIC X(40).
       FD OUT.
       01 OUT-REC PIC X(46).
       WORKING-STORAGE SECTION.
       01 IN-ST           PIC XX.
       01 WS-EOF          PIC X VALUE "N".
       01 WS-ANNUAL-CENTS PIC 9(10).
       01 WS-INC-CENTS    PIC 9(10).
       01 WS-TOTAL-CENTS  PIC 9(10).
       01 WS-ADOLS        PIC 9(6).
       01 WS-AREM         PIC 9(2).
       01 WS-TDOLS        PIC 9(6).
       01 WS-TREM         PIC 9(2).
       01 WS-LINE         PIC X(46).
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT INP
           OPEN OUTPUT OUT
           PERFORM UNTIL WS-EOF = "Y"
               READ INP
                   AT END MOVE "Y" TO WS-EOF
                   NOT AT END PERFORM PROCESS-REC
               END-READ
           END-PERFORM
           CLOSE INP
           CLOSE OUT
           STOP RUN.
       PROCESS-REC.
           COMPUTE WS-ANNUAL-CENTS = IN-RATE * 1200
           IF IN-YEARS > 0
               COMPUTE WS-INC-CENTS = (IN-BONUS / IN-YEARS) * 100
           ELSE
               MOVE 0 TO WS-INC-CENTS
           END-IF
           COMPUTE WS-TOTAL-CENTS = WS-ANNUAL-CENTS + WS-INC-CENTS
           DIVIDE WS-ANNUAL-CENTS BY 100 GIVING WS-ADOLS
                   REMAINDER WS-AREM
           DIVIDE WS-TOTAL-CENTS BY 100 GIVING WS-TDOLS
                   REMAINDER WS-TREM
           MOVE SPACES TO WS-LINE
           STRING IN-ID " " IN-NAME " "
                  WS-ADOLS "." WS-AREM " "
                  WS-TDOLS "." WS-TREM
               DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           WRITE OUT-REC FROM WS-LINE.