package cairn;

/**
 * Installs the daemon's termination handler.
 *
 * The JVM invokes the registered shutdown hook when the process receives
 * SIGTERM (or SIGINT), and only exits the process once the hook has returned,
 * so the hook IS the daemon's graceful-shutdown path: drain the worker pool,
 * stop the ticker, close (flush + sync) the journal, return.
 *
 * The drain below takes the journal's own mutex first. The idea is that the
 * whole stop sequence runs as one critical section against the journal: no
 * worker entry can sneak past the drain, and the journal is quiescent before
 * it is closed. {@link Journal#append} takes the same mutex for every line.
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

        // Hold the journal mutex across the whole stop sequence so the
        // journal is quiescent while we wait for the workers.
        synchronized (daemon.journal.mutex()) {
            try {
                // First make sure every worker is done. The workers exit on
                // their own once the queue dries up, so this should be quick.
                daemon.pool.joinAll();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            try {
                // Then wait for the ticker to finish its current beat.
                daemon.ticker.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        try {
            daemon.journal.close();
        } finally {
            System.out.println("kedd: journal closed, exiting");
            System.out.flush();
        }
    }
}