import com.google.common.base.Splitter;
import com.google.common.collect.Lists;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Self-checking reproduction of the zero-width-pattern split bug (authored by
 * the oracle; the agent raises its own under the same contract).
 *
 * Public API only; compiles against the pre-fix library unchanged. Prints each
 * computed result, then exits 0 iff every case matches the correct behaviour.
 *
 * Cases:
 *  - "f" split on the word-boundary pattern \b: with the bug, the whole input
 *    is dropped and the result is EMPTY; correct is ["f"].
 *  - "foo" split on lookahead|lookbehind around 'o': with the bug the final
 *    'o' is dropped; correct is ["f", "o", "o"].
 */
public class SplitRepro {
  static int failures = 0;

  static void check(String label, Iterable<String> got, List<String> want) {
    List<String> g = Lists.newArrayList(got);
    System.out.println(label + " = " + g);
    if (!g.equals(want)) {
      System.err.println("FAIL " + label + ": got " + g + ", want " + want);
      failures++;
    }
  }

  public static void main(String[] args) {
    check("word-boundary-single-char",
        Splitter.on(Pattern.compile("\\b")).split("f"),
        Arrays.asList("f"));
    check("lookaround-mid-string",
        Splitter.onPattern("(?=o)|(?<=o)").split("foo"),
        Arrays.asList("f", "o", "o"));
    if (failures > 0) {
      System.err.println(failures + " case(s) failed: the splitter dropped "
          + "the final piece for a zero-width-capable pattern");
      System.exit(1);
    }
    System.out.println("OK");
  }
}