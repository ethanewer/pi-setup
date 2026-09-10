package cairn;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.channels.FileChannel;

/**
 * kedd journal daemon entry point.
 *
 * Lifecycle: the daemon parses and validates the workload file, opens the
 * journal, enqueues every event with the worker pool (all events are
 * accepted before readiness is reported), starts the ticker, writes the
 * readiness marker, and then simply waits. From there on the process is
 * terminated by SIGTERM: the JVM runs {@link ShutdownHook}, which drains the
 * pool, stops the ticker and closes (flushes) the journal before the JVM
 * exits. See the project README for the full operation contract.
 */
public final class Keddaemon {

    /** Number of worker threads in the ingest pool. */
    public static final int POOL_SIZE = 4;

    final Journal journal;
    final WorkerPool pool;
    final Ticker ticker;

    private Keddaemon(Journal journal, WorkerPool pool, Ticker ticker) {
        this.journal = journal;
        this.pool = pool;
        this.ticker = ticker;
    }

    public static void main(String[] args) {
        try {
            run(args);
        } catch (UsageException ue) {
            System.err.println("kedd: " + ue.getMessage());
            System.err.println("usage: kedd --workload <file> --journal <file>"
                    + " --ready <file> --state <dir>");
            System.exit(2);
        } catch (Throwable t) {
            System.err.println("kedd: fatal: " + t);
            System.exit(2);
        }
    }

    static void run(String[] args) throws Exception {
        Config cfg = Config.parse(args);
        Event[] events = Workload.load(cfg.workload);
        if (events.length == 0) {
            throw new UsageException("workload " + cfg.workload + " has no events");
        }
        Files.createDirectories(cfg.stateDir);
        Journal journal = new Journal(cfg.journal);
        WorkerPool pool = new WorkerPool(POOL_SIZE, journal);
        Ticker ticker = new Ticker(cfg.stateDir);
        Keddaemon daemon = new Keddaemon(journal, pool, ticker);

        ShutdownHook.install(daemon);
        daemon.start(events);
        writeReadyMarker(cfg.ready);
        System.out.println("kedd ready with " + events.length + " events");
        System.out.flush();
        daemon.blockUntilTerminated();
    }

    private void start(Event[] events) {
        pool.start();
        for (Event event : events) {
            pool.submit(event);
        }
        ticker.start();
    }

    private void blockUntilTerminated() {
        for (;;) {
            try {
                Thread.sleep(3_600_000L);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private static void writeReadyMarker(Path ready) throws IOException {
        try (FileChannel ch = FileChannel.open(ready,
                StandardOpenOption.CREATE,
                StandardOpenOption.TRUNCATE_EXISTING,
                StandardOpenOption.WRITE)) {
            ch.write(ByteBuffer.wrap("READY\n".getBytes(StandardCharsets.UTF_8)));
            ch.force(true);
        }
    }

    /** Parsed command line; every flag is required. */
    static final class Config {
        final Path workload;
        final Path journal;
        final Path ready;
        final Path stateDir;

        private Config(Path workload, Path journal, Path ready, Path stateDir) {
            this.workload = workload;
            this.journal = journal;
            this.ready = ready;
            this.stateDir = stateDir;
        }

        static Config parse(String[] args) throws UsageException {
            Path workload = null;
            Path journal = null;
            Path ready = null;
            Path stateDir = null;
            for (int i = 0; i < args.length; i++) {
                String flag = args[i];
                String value;
                if (i + 1 >= args.length) {
                    throw new UsageException("missing value for " + flag);
                }
                value = args[++i];
                switch (flag) {
                    case "--workload": workload = Path.of(value); break;
                    case "--journal": journal = Path.of(value); break;
                    case "--ready": ready = Path.of(value); break;
                    case "--state": stateDir = Path.of(value); break;
                    default:
                        throw new UsageException("unknown flag " + flag);
                }
            }
            if (workload == null || journal == null || ready == null || stateDir == null) {
                throw new UsageException("all of --workload/--journal/--ready/--state are required");
            }
            return new Config(workload, journal, ready, stateDir);
        }
    }

    static final class UsageException extends Exception {
        UsageException(String message) {
            super(message);
        }
    }
}