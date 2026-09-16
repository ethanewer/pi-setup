import com.google.common.io.ByteSource;

/**
 * Direct reproduction of the reported symptom: slice an already-sliced byte
 * source with an offset past the first slice's length. The javadoc contract
 * promises an EMPTY source here; on the buggy tree this instead throws
 * IllegalArgumentException ("length (-1) may not be negative"), which this
 * program turns into a clear BUG: line and exit code 1. On a correct tree it
 * prints "no exception; isEmpty=true" and exits 0.
 *
 * Only public API is used; this is exactly the recipe in instruction.md.
 */
public class Reproducer {
  public static void main(String[] args) throws Exception {
    try {
      ByteSource s = ByteSource.concat().slice(0, 3).slice(4, 3);
      System.out.println("no exception; isEmpty=" + s.isEmpty());
      if (!s.isEmpty()) {
        System.exit(1);
      }
      System.out.println("OK");
    } catch (IllegalArgumentException e) {
      System.out.println("BUG: IllegalArgumentException thrown: " + e.getMessage());
      System.exit(1);
    }
  }
}