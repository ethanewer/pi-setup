package cairn;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.channels.FileChannel;
import java.time.Instant;

/**
 * Heartbeat thread. Every quarter second it appends a TICK line to
 * <state>/tick.log so operators can see the daemon is alive even while the
 * queue is idle.
 *
 * The ticker is an ordinary (non-daemon) thread by design: the daemon's
 * liveness is the liveness of its threads, and nothing should end the JVM
 * while the ticker is still expected to beat. Any stop of the ticker must be
 * explicit, from the daemon's shutdown path.
 */
public final class Ticker extends Thread {

    private final Path tickFile;

    public Ticker(Path stateDir) throws IOException {
        super("kedd-ticker");
        this.tickFile = stateDir.resolve("tick.log");
    }

    public Path tickFile() {
        return tickFile;
    }

    @Override
    public void run() {
        for (;;) {
            try {
                Thread.sleep(250L);
                appendTick();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private void appendTick() {
        try (FileChannel ch = FileChannel.open(tickFile,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND,
                StandardOpenOption.WRITE)) {
            byte[] line = ("TICK " + Instant.now() + "\n")
                    .getBytes(StandardCharsets.UTF_8);
            ch.write(ByteBuffer.wrap(line));
        } catch (IOException e) {
            System.err.println("kedd: tick write failed: " + e.getMessage());
        }
    }
}