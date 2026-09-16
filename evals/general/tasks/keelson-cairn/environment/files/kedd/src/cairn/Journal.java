package cairn;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.channels.FileChannel;
import java.util.Objects;

/**
 * Ordered, durable journal for processed events.
 *
 * Appends are serialized on a private mutex and each line is fsynced before
 * the next line is admitted, so a crash can only ever lose a whole suffix of
 * the workload - never a prefix, and never reorder anything. Entries must be
 * presented in ascending ordinal order: concurrent producers (the worker
 * threads) wait on the mutex for their ordinal's turn, which is what makes
 * the on-disk file strictly ordered no matter how the workers interleave.
 *
 * The mutex is exposed (package-private) because the shutdown path must be
 * able to serialize against in-flight appends. {@link ShutdownHook} relies on
 * this to make sure no entry can slip past the drain.
 */
public final class Journal {

    private final Object mutex = new Object();
    private final FileChannel channel;
    private final Path path;
    private long nextOrdinal = 0;

    public Journal(Path path) throws IOException {
        this.path = Objects.requireNonNull(path);
        this.channel = FileChannel.open(path,
                StandardOpenOption.CREATE,
                StandardOpenOption.TRUNCATE_EXISTING,
                StandardOpenOption.WRITE);
    }

    public Path path() {
        return path;
    }

    Object mutex() {
        return mutex;
    }

    /**
     * Appends one journal line for the event and synces it to disk.
     * Blocking and ordered: returns only once the line is durable and all
     * lower ordinals are already on disk.
     */
    public void append(int ordinal, String payload, String digest)
            throws IOException {
        String line = ordinal + "|" + payload + "|" + digest + "\n";
        byte[] bytes = line.getBytes(StandardCharsets.UTF_8);
        synchronized (mutex) {
            while (ordinal != nextOrdinal) {
                try {
                    mutex.wait();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            writeAndSync(bytes);
            nextOrdinal++;
            mutex.notifyAll();
        }
    }

    /**
     * Flushes and closes the journal. Intended to be called once every
     * producer has stopped appending - normally from the shutdown path
     * after the worker threads have been joined.
     */
    public void close() {
        synchronized (mutex) {
            try {
                channel.force(true);
            } catch (IOException e) {
                System.err.println("kedd: final sync failed: " + e.getMessage());
            }
            try {
                channel.close();
            } catch (IOException e) {
                System.err.println("kedd: journal close failed: " + e.getMessage());
            }
        }
    }

    private void writeAndSync(byte[] bytes) throws IOException {
        channel.write(ByteBuffer.wrap(bytes));
        channel.force(false);
    }
}