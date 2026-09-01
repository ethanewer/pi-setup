#pragma once
#include <stdio.h>

/* Apply the plotting job in fh to the canvas. Blank lines and lines whose
 * first character is '#' are skipped. A line is applied only when the verb
 * is known and it carries exactly the right number of integer arguments:
 *   dot X Y | hline X1 X2 Y | vline X Y1 Y2 | rect X Y W H | fill X Y W H | clear
 * Anything else is skipped without error. Returns the number of applied
 * commands. */
int pl_run_job(unsigned char *pix, FILE *fh);
