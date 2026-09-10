package cairn;

/**
 * One workload event: an ordinal, an opaque payload token, and a processing
 * width. Instances are immutable. The singleton {@link #POISON} marks the
 * end of the queue and is never a real event (its ordinal is -1).
 */
public final class Event {

    /** Sentinel used by the worker pool to signal stop to worker threads. */
    public static final Event POISON = new Event(-1, "POISON", -1);

    public final int ordinal;
    public final String payload;
    public final int width;

    public Event(int ordinal, String payload, int width) {
        this.ordinal = ordinal;
        this.payload = payload;
        this.width = width;
    }

    /** The exact string the journal digest is computed over. */
    public String digestInput() {
        return ordinal + ":" + payload + ":" + width;
    }
}