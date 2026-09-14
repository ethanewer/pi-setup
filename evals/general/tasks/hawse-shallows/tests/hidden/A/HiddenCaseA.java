import com.google.common.base.Splitter;
import com.google.common.collect.Lists;
import java.util.Arrays;

/**
 * Hidden case A (authored): lookahead|lookbehind alternation with several
 * matched letter positions. With the bug present, the zero-width match exactly
 * at end-of-string stops iteration before the final piece ("a") is emitted:
 * the result misses the last character. The upstream regression test does not
 * exercise this input or pattern shape.
 */
public class HiddenCaseA {
  public static void main(String[] args) {
    Iterable<String> parts = Splitter.onPattern("(?=n)|(?<=n)").split("banana");
    java.util.List<String> got = Lists.newArrayList(parts);
    System.out.println(got);
    if (!got.equals(Arrays.asList("ba", "n", "a", "n", "a"))) {
      System.err.println("WRONG RESULT: " + got);
      System.exit(1);
    }
    System.out.println("OK-A");
  }
}