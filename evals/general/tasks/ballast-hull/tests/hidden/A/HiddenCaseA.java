import com.google.common.collect.ImmutableSet;
import java.util.Arrays;

/**
 * Hidden case A (authored): reuse a sized immutable-set Builder across builds,
 * different expected size and element type than the upstream regression test.
 * After the first build shrinks the internal table, enough further elements are
 * added to pack it full; on the buggy tree a contains() call then never returns.
 */
public class HiddenCaseA {
  public static void main(String[] args) {
    // expected size 20 -> initial table 32; first build drops 3 strings, review
    // shrinks the table to 8. Reuse then packs 8 strings into that 8-cell table.
    ImmutableSet.Builder<String> b = ImmutableSet.builderWithExpectedSize(20);
    b.add("alpha", "bravo", "charlie");
    ImmutableSet<String> unused = b.build();
    ImmutableSet<String> s = b.add("delta", "echo", "foxtrot", "golf", "hotel").build();
    boolean present = s.contains("alpha") && s.contains("delta") && s.contains("hotel");
    boolean absent = s.contains("zulu");
    System.out.println("members=" + Arrays.toString(s.toArray()));
    System.out.println("present=" + present);
    System.out.println("absent=" + absent);
    if (s.size() != 8 || !present || absent) {
      System.err.println("WRONG RESULT");
      System.exit(1);
    }
    System.out.println("OK-A");
  }
}