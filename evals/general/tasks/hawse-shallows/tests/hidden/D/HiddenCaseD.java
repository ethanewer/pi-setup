import com.google.common.base.Splitter;
import com.google.common.collect.Lists;
import java.util.Arrays;

/**
 * Hidden case D (authored): repeated alternating lookarounds over a longer
 * input with repeated letters. Every separator is zero-width and the final
 * match sits exactly at end-of-string; with the bug present the trailing "i"
 * is dropped. Longer, letter-heavier input than the upstream regression test.
 */
public class HiddenCaseD {
  public static void main(String[] args) {
    Iterable<String> parts = Splitter.onPattern("(?=i)|(?<=i)").split("Mississippi");
    java.util.List<String> got = Lists.newArrayList(parts);
    System.out.println(got);
    if (!got.equals(Arrays.asList("M", "i", "ss", "i", "ss", "i", "pp", "i"))) {
      System.err.println("WRONG RESULT: " + got);
      System.exit(1);
    }
    System.out.println("OK-D");
  }
}