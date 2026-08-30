/*
 * flint shared default library.
 * Exports core_answer(int n) -> int. Compile as a shared object:
 *   gcc -shared -fPIC -o libcore.so core.c
 */
int core_answer(int n) {
    return n * 7 + 11;
}
