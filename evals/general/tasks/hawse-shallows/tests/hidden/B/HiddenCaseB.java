import com.google.common.base.Splitter;
import com.google.common.collect.Lists;
import java.util.Arrays;
import java.util.regex.Pattern;

/**
 * Hidden case B (authored): word-boundary pattern where the word ends in the
 * middle of the input, leaving a trailing non-word piece. With the bug present
 * the zero-width boundary match at the end of the word stops iteration and the
 * trailing "." is dropped. The upstream regression test only splits inputs
 * that END in a word character, so this input shape is not covered there.
 */
public class HiddenCaseB {
  public static void main(String[] args) {
    Iterable<String> parts = Splitter.on(Pattern.compile("\\b")).split("foo.");
    java.util.List<String> got = Lists.newArrayList(parts);
    System.out.println(got);
    if (!got.equals(Arrays.asList("foo", "."))) {
      System.err.println("WRONG RESULT: " + got);
      System.exit(1);
    }
    System.out.println("OK-B");
  }
}