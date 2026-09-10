# mizzen-summit build notes

This directory is intentionally near-empty: the task's whole world is the
upstream apache/kafka tree that `environment/Dockerfile` clones (shallow,
pinned to commit 26b251a451ce941d3d7a55e6487bcb7f16b5ad48 = the peeled ref of
tag 4.3.1). Nothing upstream is vendored into this task tree.

The Dockerfile only adds the build's *toolchain* (JDK 21, git), warms the
Gradle distribution / plugin set / dependency jars / compiled module outputs
under /app/.gradle-home and /app/src/*/build, and fixes ownership so the trial
can run as uid 1000. No upstream bytes live here.