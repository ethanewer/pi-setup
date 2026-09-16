import com.google.common.io.ByteSource;
import com.google.common.io.ByteStreams;

/**
 * Hidden case: consume the re-sliced source through ByteStreams.toByteArray.
 * The data is behind a {@code concat} so the slicing goes through the default
 * {@code ByteSource.slice} implementation (the same code path as the reported
 * bug). A re-slice whose offset is past the window's length must behave as an
 * empty source: reading it yields zero bytes rather than throwing
 * IllegalArgumentException ("length (-6) may not be negative") as it does on
 * the buggy tree.
 */
public class StreamSlice {
  public static void main(String[] args) throws Exception {
    byte[] data = new byte[] {1, 2, 3, 4, 5, 6, 7, 8};
    ByteSource s = ByteSource.concat(ByteSource.wrap(data)).slice(4, 4).slice(10, 2);
    byte[] out = ByteStreams.toByteArray(s.openStream());
    System.out.println("len=" + out.length);
    if (out.length != 0) {
      System.exit(1);
    }
    System.out.println("OK");
  }
}