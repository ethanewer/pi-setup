package cairn;

/**
 * Installs the daemon's termination handler.
 *
 * The JVM invokes the registered shutdown hook when the process receives
 * SIGTERM (or SIGINT), and only exits the process once the hook has returned,
 * so the hook IS the daemon's graceful-shutdown path: stop the worker pool,
 * stop the ticker, close (flush + sync) the journal, return.
 *
 * Order is critical and is: stop-both-threads-first, join-both-threads, then
 * touch the journal. No lock is taken across the joins: the journal's append
 * mutex belongs to the workers, and holding it while waiting for workers
 * that still have to append would deadlock the drain. Instead the pool is
 * told to drain (it finishes every accepted event) and only once every
 * worker has exited is the journal closed. Because the pool's drain finishes
 * all queued events and appends are serialized and ordered inside the
 * journal, the on-disk file is complete and strictly ordered when the hook
 * returns, and the JVM can exit.
 */
public final class ShutdownHook {

    private ShutdownHook() {
    }

    public static void install(Keddaemon daemon) {
        Runtime.getRuntime().addShutdownHook(
                new Thread(() -> onTerm(daemon), "kedd-shutdown"));
    }

    static void onTerm(Keddaemon daemon) {
        System.out.println("kedd: SIGTERM received, beginning graceful shutdown");
        System.out.flush();

        // 1) Stop accepting work and stop the housekeeping threads.
        daemon.pool.shutdown();
        daemon.ticker.requestStop();

        // 2) Wait for the drain: workers finish every accepted event and
        //    exit; the ticker ends its current beat. No journal lock is
        //    held here, so workers can append freely until they observe
        //    their poison sentinel.
        try {
            daemon.pool.joinAll();
            daemon.ticker.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // 3) Quiescence reached: flush and close the journal. Every event
        //    accepted at readiness is on disk, in ordinal order.
        try {
            daemon.journal.close();
        } finally {
            System.out.println("kedd: journal flushed and closed, exiting");
        }
    }
}