package cairn;

import java.util.concurrent.LinkedBlockingQueue;

/**
 * Fixed-size pool of worker threads.
 *
 * Events are submitted by the daemon at startup, processed in FIFO order by
 * whichever worker is free, and each result is journaled by the worker that
 * ran it. The pool is intentionally bare: it can start, accept work, and be
 * joined after the event queue is exhausted - nothing in this class owns the
 * daemon's lifecycle.
 *
 * Workers are ordinary (non-daemon) threads; the JVM stays alive as long as
 * a worker is parked on the queue, which is what keeps the daemon's
 * journaling alive. {@link #joinAll()} waits for the workers to finish on
 * their own, so it is only expected to return once every event has been
 * consumed and processed.
 */
public final class WorkerPool {

    /** Simulated processing cost per width unit (nanoseconds). */
    private static final long WIDTH_UNIT_NANOS = 25_000L;

    private final Thread[] workers;
    private final LinkedBlockingQueue<Event> queue = new LinkedBlockingQueue<>();
    private final Journal journal;

    public WorkerPool(int workerCount, Journal journal) {
        this.journal = journal;
        this.workers = new Thread[workerCount];
        for (int i = 0; i < workerCount; i++) {
            workers[i] = new Thread(this::runLoop, "kedd-worker-" + i);
        }
    }

    public void start() {
        for (Thread worker : workers) {
            worker.start();
        }
    }

    /** Blocks if the queue is full; no event can be lost once accepted. */
    public void submit(Event event) {
        try {
            queue.put(event);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("submit interrupted", e);
        }
    }

    /**
     * Waits for every worker thread to finish on its own. Only returns once
     * each worker has left {@link #runLoop}.
     */
    public void joinAll() throws InterruptedException {
        for (Thread worker : workers) {
            worker.join();
        }
    }

    public int workerCount() {
        return workers.length;
    }

    private void runLoop() {
        for (;;) {
            final Event event;
            try {
                event = queue.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            process(event);
        }
    }

    private void process(Event event) {
        java.util.concurrent.locks.LockSupport.parkNanos(
                event.width * WIDTH_UNIT_NANOS);
        try {
            journal.append(event.ordinal, event.payload,
                    Digest.shortHex(event.digestInput()));
        } catch (java.io.IOException e) {
            System.err.println("kedd: journal write failed for event "
                    + event.ordinal + ": " + e.getMessage());
        }
    }
}