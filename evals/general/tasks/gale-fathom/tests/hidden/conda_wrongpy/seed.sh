#!/bin/bash
# Edge: miniconda is already installed but conda env "gale311" has the WRONG python
# version (3.10 instead of the requested 3.11). Provisioner must recreate the env
# with python 3.11 and re-install the pinned package into it.
CB=/app/miniconda3/bin/conda
"$CB" env remove -y -n gale311 >/dev/null 2>&1 || true
"$CB" create -q -y -n gale311 python=3.10
