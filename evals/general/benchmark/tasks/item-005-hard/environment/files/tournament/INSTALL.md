# Legacy Core War tournament: building pMARS on a modern toolchain

This tournament harness battles a Redcode "warrior" you write against the fixed
opponents in `opponents/` using the **pMARS** Core War simulator (a portable
Memory Array Redcode Simulator).

## The legacy build instructions (circa 2000)

The pMARS **Debian source package** was once fetched from an internal mirror at:

    http://mirror.internal/debian/pmars-src.tar.gz

That mirror has gone dark. A trusted fallback copy of the source tarball has been
extracted for you at:

    /app/pmars-src  (src/ contains the C sources; config.h has the variant flags)

The legacy unix build (see `/app/pmars-src/src/Makefile`) uses gcc and a number
of preprocessor selector flags. In particular the graphical **X11 display**
variant (`XDWINGRAPHX`) requires X11 dev headers + an X server. This is a
headless server — there is no display. The **tournament / server variant**
(`-DSERVER`, no display module) is the one used for automated KotH-style chests
on headless hosts and needs no X11 at all. Choose that variant, or otherwise
keep the build display-free, so the binary can run without an X server.

### Building

The distilled step is (details live in `src/config.h` and src reference docs):

    cd /app/pmars-src/src
    make -f Makefile all          # yields src/pmars

If the legacy Makefile's gcc flags are only warnings on a modern gcc, that is
fine; the binary still builds.

## Installing the artifact at the harness path

The harness (`benchmark.sh`) invokes a binary at the **absolute path**
`/app/pmars`. After building under `/app/pmars-src/src`, install it there (copy
or symlink), for example:

    cp /app/pmars-src/src/pmars /app/pmars

Do not change the path the harness uses — it must be `/app/pmars`.

## Writing your warrior in Redcode

Core War warriors are written in the **Redcode** assembly language (see
`/app/pmars-src/doc/redcode.ref` and see `/app/pmars-src/examples/simple_warrior.red`
as a starter). Your submission must be a plain `.red` text file:

    /app/tournament/mine.red

## Running and optimizing

To score your current warrior against the visible opponents:

    cd /app/tournament
    ./benchmark.sh mine.red

The metric that matters is **points** = `(wins + 0.5 * draws) / games` across all
opponents. Wins are worth 1.0, draws 0.5 (both count as "you did not lose").
Iterate empirically: edit `mine.red`, rerun `./benchmark.sh mine.red`, and raise
the points. `-f` is used by the harness so the RNG seed is derived from the
warrior bytes, i.e. results are reproducible for a given file.

## The exact submission & invocation

- The harness MUST be run exactly as `./benchmark.sh mine.red` (with your warrior
  as the first argument).
- The binary MUST be at `/app/pmars`.
- Your warrior MUST be at `/app/tournament/mine.red`.
- Do not modify anything under `/app/tournament/opponents/` — those are the
  graders' fixed opponents and are treated as immutable inputs.