import com.google.common.base.Splitter;
import com.google.common.collect.Lists;
import java.util.Arrays;

/**
 * Hidden case C (authored): lookbehind-only pattern whose every match is
 * zero-width, including one exactly at the end of the input. With the bug
 * present the match at position == length() terminates iteration one piece
 * early ("fooo" loses its final "o"). Pattern class (bare lookbehind) and
 * input differ from the upstream regression test.
 */
public class HiddenCaseC {
  public static void main(String[] args) {
    Iterable<String> parts = Splitter.onPattern("(?<=o)").split("fooo");
    java.util.List<String> got = Lists.newArrayList(parts);
    System.out.println(got);
    if (!got.equals(Arrays.asList("fo", "o", "o"))) {
      System.err.println("WRONG RESULT: " + got);
      System.exit(1);
    }
    System.out.println("OK-C");
  }
}