/* seed/classify.c - the visible target for the symbolic execution engine.

   `target` branches on its single signed-int argument. The symbolic engine
   must explore BOTH control-flow branches and emit one reachable concrete
   test input per branch.
*/
int target(int x) {
    int y = 3 * x + 5;
    if (y > 41) return 41;   /* HIGH branch: needs x >= 13 */
    return 73;               /* LOW  branch: x <= 12      */
}