import com.google.common.io.ByteSource;

/**
 * Hidden case: re-slice a slice of a NON-EMPTY source with an offset past the
 * window's length. The data is behind a {@code concat} so the slicing goes
 * through the default {@code ByteSource.slice} implementation (the same code
 * path as the reported bug). The javadoc contract promises an empty source; on
 * the buggy tree this throws IllegalArgumentException ("length (-5) may not be
 * negative").
 */
public class BiggerSlice {
  public static void main(String[] args) throws Exception {
    byte[] data = new byte[64];
    for (int i = 0; i < data.length; i++) {
      data[i] = (byte) i;
    }
    ByteSource s = ByteSource.concat(ByteSource.wrap(data)).slice(10, 20).slice(25, 5);
    boolean empty = s.isEmpty();
    byte[] out = s.read();
    System.out.println("isEmpty=" + empty);
    System.out.println("readLen=" + out.length);
    if (!empty || out.length != 0) {
      System.exit(1);
    }
    System.out.println("OK");
  }
}