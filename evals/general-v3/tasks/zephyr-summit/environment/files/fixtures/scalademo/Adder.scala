package summit

object Arith {
  /** weight(n) = n^2 + 3n + 7; deterministic so results are checkable. */
  def weigh(n: Int): Int = n * n + 3 * n + 7
}
