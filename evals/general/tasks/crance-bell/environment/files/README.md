# crance-bell task

This directory is the environment for the crance-bell task. It contains no
source code: the working tree ships inside the image, cloned at build time
from upstream scipy/scipy at the pinned parent commit (see Dockerfile).
This file exists only so `COPY files/ /app/` has something to copy and
creates the /app directory for the agent's deliverable.