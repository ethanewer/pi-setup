trunnel-reach fixtures.

The visible challenge binary is compiled inside environment/Dockerfile from an
authored C source (never shipped — the task is binary analysis). Hidden cases
under ../tests/hidden are self-contained C sources compiled fresh by the
verifier; every binary shares the same program shape with different constants.