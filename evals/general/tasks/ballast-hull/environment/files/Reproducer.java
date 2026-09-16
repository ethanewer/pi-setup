import com.google.common.collect.ImmutableSet;

/**
 * Direct reproduction of the reported symptom: build one set from a sized
 * builder, then REUSE the same builder to build a second, larger set. On the
 * buggy tree the final contains(4) call never returns (hangs); on a correct
 * tree it returns false and this program prints both lines and exits 0.
 *
 * Only public API is used; this is exactly the recipe in instruction.md.
 */
public class Reproducer {
  public static void main(String[] args) {
    ImmutableSet.Builder<Object> b = ImmutableSet.builderWithExpectedSize(6);
    b.add(0);
    ImmutableSet<Object> unused = b.build();
    ImmutableSet<Object> subject = b.add(1).add(2).add(3).build();
    boolean c = subject.contains(4);
    System.out.println("contains(4)=" + c + " subject=" + subject);
    if (c) {
      System.exit(1);
    }
    System.out.println("OK");
  }
}
