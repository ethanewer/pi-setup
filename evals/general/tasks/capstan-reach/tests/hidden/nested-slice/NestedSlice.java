import com.google.common.io.ByteSource;

/**
 * Hidden case: THREE levels of slicing (an empty concat source), where the
 * final re-slice starts past the current window's length. The result must be
 * an empty source whose stream reads EOF (-1) and which can itself be
 * re-sliced without error; on the buggy tree the final slice throws
 * IllegalArgumentException ("length (-2) may not be negative").
 */
public class NestedSlice {
  public static void main(String[] args) throws Exception {
    ByteSource s = ByteSource.concat().slice(0, 7).slice(3, 4).slice(6, 1);
    boolean empty = s.isEmpty();
    int first = s.openStream().read();
    boolean stillEmpty = s.slice(0, 5).isEmpty();
    System.out.println("isEmpty=" + empty);
    System.out.println("read1=" + first);
    System.out.println("reSliceEmpty=" + stillEmpty);
    if (!empty || first != -1 || !stillEmpty) {
      System.exit(1);
    }
    System.out.println("OK");
  }
}