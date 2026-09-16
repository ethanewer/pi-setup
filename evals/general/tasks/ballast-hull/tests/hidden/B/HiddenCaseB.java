import com.google.common.collect.ImmutableSet;
import java.util.Arrays;

/**
 * Hidden case B (authored): reuse a builder created with a larger expected size,
 * where the first build drops 9 elements (so the retained table shrinks to 16)
 * and the reused builder then adds enough to pack that 16-cell table completely.
 * Different expected size, first-build size and final size than the upstream
 * regression test (which reaches a 4-cell table).
 */
public class HiddenCaseB {
  public static void main(String[] args) {
    // expected size 40 -> initial table 64 (threshold 44). First build of 9 ints
    // makes review() shrink the table to 16, but (on the buggy tree) leaves the
    // large thresholds behind. Reusing to add 7 more packs the 16-cell table.
    ImmutableSet.Builder<Integer> b = ImmutableSet.builderWithExpectedSize(40);
    for (int i = 0; i <= 8; i++) {
      b.add(i);
    }
    ImmutableSet<Integer> unused = b.build();
    ImmutableSet<Integer> s = b.add(9).add(10).add(11).add(12).add(13).add(14).add(15).build();
    boolean present = s.contains(15) && s.contains(0) && s.contains(8);
    boolean absent = s.contains(9999);
    System.out.println("members=" + Arrays.toString(s.toArray()));
    System.out.println("present=" + present);
    System.out.println("absent=" + absent);
    if (s.size() != 16 || !present || absent) {
      System.err.println("WRONG RESULT");
      System.exit(1);
    }
    System.out.println("OK-B");
  }
}