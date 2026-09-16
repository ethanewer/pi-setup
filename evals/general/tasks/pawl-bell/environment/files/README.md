# pawl-bell: build a real chess engine and drive its UCI protocol

This task ships **no fixture source code**. The upstream repository
`official-stockfish/Stockfish` is cloned at build time into the image at
`/app/src`, pinned by commit `59aae690f91d6f69aac194f447d84b4a2c3be778`
(verified with `git ls-remote`; it is upstream HEAD), and left unbuilt.

The agent must build `/app/src/src/stockfish` with the project's own Makefile
and write `/app/uci_play.py`, a UCI protocol driver (position setup, fixed
depth search, reading back best move and centipawn score).

Nothing in this directory is upstream code; the checkout lives only in the
image at build time.