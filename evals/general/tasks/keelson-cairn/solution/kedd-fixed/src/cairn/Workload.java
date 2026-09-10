package cairn;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Parses and validates kedd workload files.
 *
 * Format: one event per line,
 *
 *     <ordinal>,<payload>,<width>
 *
 * with '#'-prefixed comment lines and blank lines ignored. Ordinals must run
 * 0..N-1 contiguously in file order, payloads must match
 * [A-Za-z0-9._-]+ and widths must be in 0..2000. A malformed workload is
 * rejected at startup rather than processed.
 */
public final class Workload {

    private Workload() {
    }

    /** Raised when a workload file does not follow the format contract. */
    public static final class ParseException extends Exception {
        public ParseException(String message) {
            super(message);
        }
    }

    public static Event[] load(Path path) throws IOException, ParseException {
        List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
        List<Event> events = new ArrayList<>();
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i).trim();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }
            String[] parts = line.split(",");
            if (parts.length != 3) {
                throw new ParseException(
                        "line " + (i + 1) + ": expected exactly 3 comma-separated"
                                + " fields, found " + parts.length);
            }
            int ordinal;
            int width;
            try {
                ordinal = Integer.parseInt(parts[0].trim());
                width = Integer.parseInt(parts[2].trim());
            } catch (NumberFormatException nfe) {
                throw new ParseException(
                        "line " + (i + 1) + ": ordinal and width must be integers");
            }
            String payload = parts[1].trim();
            if (payload.isEmpty() || !payload.matches("[A-Za-z0-9._-]+")) {
                throw new ParseException(
                        "line " + (i + 1) + ": payload must match [A-Za-z0-9._-]+");
            }
            if (ordinal != events.size()) {
                throw new ParseException(
                        "line " + (i + 1) + ": ordinal " + ordinal
                                + " out of sequence (expected " + events.size() + ")");
            }
            if (width < 0 || width > 2000) {
                throw new ParseException(
                        "line " + (i + 1) + ": width " + width
                                + " out of range 0..2000");
            }
            events.add(new Event(ordinal, payload, width));
        }
        return events.toArray(new Event[0]);
    }
}