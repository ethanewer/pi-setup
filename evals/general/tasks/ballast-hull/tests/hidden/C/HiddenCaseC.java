import com.google.common.collect.ImmutableSet;
import java.util.Arrays;

/**
 * Hidden case C (authored): reuse ONE builder to build THREE separate sets.
 * The buggy tree's un-reset thresholds corrupt the retained table across
 * repeated build() calls; the third build packs the table full and a contains()
 * call hangs. A correct fix must keep all three builds correct and independent.
 */
public class HiddenCaseC {
  public static void main(String[] args) {
    ImmutableSet.Builder<String> b = ImmutableSet.builderWithExpectedSize(10);
    b.add("x");
    ImmutableSet<String> set1 = b.build();
    ImmutableSet<String> set2 = b.add("y", "z").build();
    ImmutableSet<String> set3 = b.add("w").build();

    boolean ok = set1.size() == 1
        && set1.contains("x") && !set1.contains("y")
        && set2.size() == 3
        && set2.contains("x") && set2.contains("y") && set2.contains("z")
        && set3.size() == 4
        && set3.contains("w") && set3.contains("x") && !set3.contains("q");

    System.out.println("set1=" + Arrays.toString(set1.toArray()));
    System.out.println("set2=" + Arrays.toString(set2.toArray()));
    System.out.println("set3=" + Arrays.toString(set3.toArray()));
    System.out.println("consistent=" + ok);
    if (!ok) {
      System.err.println("WRONG RESULT");
      System.exit(1);
    }
    System.out.println("OK-C");
  }
}