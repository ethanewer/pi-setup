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
 * The ticker owns its stop: {@link #requestStop()} asks it to end its loop
 * after the current beat, and the shutdown path joins it once stopped.
 * Stopping the ticker is a prerequisite for a clean process exit - as a
 * non-daemon thread it must end before the JVM may exit.
 */
public final class Ticker extends Thread {

    private final Path tickFile;
    private volatile boolean running = true;

    public Ticker(Path stateDir) throws IOException {
        super("kedd-ticker");
        this.tickFile = stateDir.resolve("tick.log");
    }

    public Path tickFile() {
        return tickFile;
    }

    /** Asks the ticker to stop after its current beat. Idempotent. */
    public void requestStop() {
        running = false;
    }

    @Override
    public void run() {
        while (running) {
            try {
                Thread.sleep(250L);
                if (running) {
                    appendTick();
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                if (!running) {
                    return;
                }
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