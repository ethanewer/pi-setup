/* brisk-wharf : parallel flow-count aggregator (MPI).
 *
 * Usage: mpi_agg <fragments.txt> <outdir>
 *   Run under mpirun:  mpirun -np N /app/mpi_agg <fragments.txt> <outdir>
 *
 * Input: lines "<contig_id>\\t<value>" (both integers).
 * Rank r owns every contig id with (id % size) == r.  For each owned contig it
 * writes, to <outdir>/flows.rank<r>.txt, one line "<id>\\t<count>\\t<sum>" (ascending
 * id), and it writes a worker marker /app/markers/mpi_rank<r>.marker.
 * Rank 0 reads the file and MPI_Send's every other rank its owned lines.
 * Running with size==1 (serial) must produce exactly the union of the per-rank
 * outputs for any size == the same aggregated result, so parallel == serial.
 */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define MAXLINE 4096

static void marker(int rank) {
    char p[512];
    snprintf(p, sizeof(p), "/app/markers/mpi_rank%d.marker", rank);
    FILE *f = fopen(p, "w");
    if (f) { fprintf(f, "rank %d contributor\n", rank); fclose(f); }
}

int main(int argc, char **argv) {
    int rank, size;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    if (argc < 3) {
        if (rank == 0) fprintf(stderr, "usage: mpi_agg <fragments.txt> <outdir>\n");
        MPI_Finalize();
        return 2;
    }
    const char *inpath = argv[1];
    const char *outdir = argv[2];
    mkdir(outdir, 0755);

    long *ids = NULL, *vals = NULL;
    int n = 0, cap = 0;

    if (rank == 0) {
        FILE *f = fopen(inpath, "r");
        if (!f) { MPI_Abort(MPI_COMM_WORLD, 3); }
        char line[MAXLINE];
        while (fgets(line, sizeof(line), f)) {
            if (line[0] == '\n' || line[0] == '\0') continue;
            long id, v;
            if (sscanf(line, "%ld\t%ld", &id, &v) != 2) continue;
            if (n == cap) {
                cap = cap ? cap * 2 : 64;
                ids = realloc(ids, (size_t)cap * sizeof(long));
                vals = realloc(vals, (size_t)cap * sizeof(long));
            }
            ids[n] = id; vals[n] = v; n++;
        }
        fclose(f);
    }
    MPI_Bcast(&n, 1, MPI_INT, 0, MPI_COMM_WORLD);
    if (rank != 0) {
        ids = malloc((size_t)n * sizeof(long));
        vals = malloc((size_t)n * sizeof(long));
    }
    MPI_Bcast(ids, n, MPI_LONG, 0, MPI_COMM_WORLD);
    MPI_Bcast(vals, n, MPI_LONG, 0, MPI_COMM_WORLD);

    /* gather owned contigs */
    long *ownc = malloc((size_t)(n + 1) * sizeof(long));
    long *owns = malloc((size_t)(n + 1) * sizeof(long));
    long *ownv = malloc((size_t)(n + 1) * sizeof(long));
    int own = 0;
    for (int i = 0; i < n; i++) {
        long m = ids[i] % size; if (m < 0) m += size;
        if (m == rank) {
            ownc[own] = ids[i]; ownv[own] = vals[i]; own++;
        }
    }
    for (int i = 0; i < own; i++) owns[i] = 0;

    /* aggregate per contig, then sort ascending by id (simple insertion on small data) */
    int k = 0;
    long *res_id = calloc(1, (size_t)(own + 1) * sizeof(long));
    long *res_cnt = calloc(1, (size_t)(own + 1) * sizeof(long));
    long *res_sum = calloc(1, (size_t)(own + 1) * sizeof(long));
    for (int i = 0; i < own; i++) {
        int idx = -1;
        for (int j = 0; j < k; j++) if (res_id[j] == ownc[i]) { idx = j; break; }
        if (idx < 0) { idx = k++; res_id[idx] = ownc[i]; res_cnt[idx] = 0; res_sum[idx] = 0; }
        res_cnt[idx]++; res_sum[idx] += ownv[i];
    }
    /* insertion sort by id */
    for (int i = 1; i < k; i++) {
        long a = res_id[i], c = res_cnt[i], s = res_sum[i];
        int j = i - 1;
        while (j >= 0 && res_id[j] > a) { res_id[j+1] = res_id[j]; res_cnt[j+1] = res_cnt[j]; res_sum[j+1] = res_sum[j]; j--; }
        res_id[j+1] = a; res_cnt[j+1] = c; res_sum[j+1] = s;
    }
    marker(rank);
    char outp[1024];
    snprintf(outp, sizeof(outp), "%s/flows.rank%d.txt", outdir, rank);
    FILE *o = fopen(outp, "w");
    if (o) {
        for (int j = 0; j < k; j++) fprintf(o, "%ld\t%ld\t%ld\n", res_id[j], res_cnt[j], res_sum[j]);
        fclose(o);
    }

    free(ids); free(vals); free(ownc); free(owns); free(ownv);
    free(res_id); free(res_cnt); free(res_sum);
    MPI_Finalize();
    return 0;
}
