/* plotsmith - the legacy grid plotter (headless core).
 *
 * Usage: plotsmith <job.txt> <out.pbm>
 * Applies the plotting job to the built-in 24x16 canvas and writes the
 * result as plain ASCII PBM. */
#include "canvas.h"
#include "front.h"
#include "job.h"
#include "pbm.h"

#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: plotsmith <job.txt> <out.pbm>\n");
        return 2;
    }
    FILE *job = fopen(argv[1], "r");
    if (job == NULL) {
        fprintf(stderr, "plotsmith: cannot open job %s\n", argv[1]);
        return 2;
    }
    unsigned char pix[PLW * PLH];
    pl_clear(pix);
    pl_run_job(pix, job);
    fclose(job);
    pl_present(pix, PLW, PLH);
    if (pl_write_pbm(argv[2], pix, PLW, PLH) != 0) {
        fprintf(stderr, "plotsmith: cannot write %s\n", argv[2]);
        return 2;
    }
    return 0;
}
