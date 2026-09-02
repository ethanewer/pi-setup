package summit

object Runner {
  def main(args: Array[String]): Unit = {
    val s = args.map(_.toInt).sum
    val r = Arith.weigh(s)
    println(s"RESULT $r")
  }
}
