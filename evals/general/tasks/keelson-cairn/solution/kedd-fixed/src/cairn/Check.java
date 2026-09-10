package cairn;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Self-check main. Exercises the workload parser, the digest rule and the
 * ordered journal writer on a SAMPLE of the workload - all single-threaded,
 * so it says nothing about the shutdown path and stays green on every
 * build. Run from the project root via tests/check.sh:
 *
 *     java -cp build cairn.Check workloads/sample/workload.txt /tmp/check.out
 */
public final class Check {

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("usage: Check <workload> <journal-out>");
            System.exit(2);
        }
        Path workload = Path.of(args[0]);
        Path journalOut = Path.of(args[1]);

        Event[] events = Workload.load(workload);
        if (events.length == 0) {
            System.err.println("check: workload is empty");
            System.exit(1);
        }

        // The parser must reject a file whose ordinals are not contiguous.
        Path bad = Files.createTempFile("kedd-check", ".wl");
        try {
            Files.writeString(bad,
                    "0,a,10\n2,b,20\n",
                    StandardCharsets.UTF_8);
            boolean rejected = false;
            try {
                Workload.load(bad);
            } catch (Workload.ParseException expected) {
                rejected = true;
            }
            if (!rejected) {
                System.err.println("check: parser accepted non-contiguous ordinals");
                System.exit(1);
            }
        } finally {
            Files.deleteIfExists(bad);
        }

        // Journal a CONTIGUOUS prefix of the workload: the ordered writer
        // admits ordinals strictly in sequence, so the sample must be
        // ordinals 0..P-1 (not a strided subset).
        Journal journal = new Journal(journalOut);
        int prefix = Math.min(60, events.length);
        for (int k = 0; k < prefix; k++) {
            Event e = events[k];
            journal.append(e.ordinal, e.payload,
                    Digest.shortHex(e.digestInput()));
        }
        journal.close();

        System.out.println("check: parsed " + events.length + " events,"
                + " journaled " + prefix + " ordered entries");
    }
}