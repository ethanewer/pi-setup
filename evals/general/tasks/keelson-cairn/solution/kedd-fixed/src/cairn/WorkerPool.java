package cairn;

import java.util.concurrent.LinkedBlockingQueue;

/**
 * Fixed-size pool of worker threads.
 *
 * Events are submitted by the daemon at startup, processed in FIFO order by
 * whichever worker is free, and each result is journaled by the worker that
 * ran it.
 *
 * The pool owns its own lifecycle: {@link #shutdown()} stops it gracefully,
 * and {@link #joinAll()} returns once every worker has ended. Shutdown is a
 * drain, not an abort: the pool finishes every event that was accepted
 * before stopping, so a clean stop of the daemon always journals the whole
 * workload. Technically it is implemented with one poison sentinel per
 * worker, offered at the tail of the FIFO, so workers consume all remaining
 * real events first and only then observe their sentinel and exit.
 */
public final class WorkerPool {

    /** Simulated processing cost per width unit (nanoseconds). */
    private static final long WIDTH_UNIT_NANOS = 25_000L;

    private final Thread[] workers;
    private final LinkedBlockingQueue<Event> queue = new LinkedBlockingQueue<>();
    private final Journal journal;
    private volatile boolean closed = false;

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
        if (closed) {
            throw new IllegalStateException("worker pool already shut down");
        }
        try {
            queue.put(event);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("submit interrupted", e);
        }
    }

    /**
     * Graceful stop: lets every queued event run, then sits one poison
     * sentinel behind them for each worker. Idempotent.
     */
    public void shutdown() {
        if (closed) {
            return;
        }
        closed = true;
        for (int i = 0; i < workers.length; i++) {
            queue.offer(Event.POISON);
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
            if (event == Event.POISON) {
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