marlinespike-wake environment/files/

This directory is deliberately empty of fixtures: the task hands the agent a
real upstream clone (prettier/prettier, pinned parent commit, dependencies
installed) in /app/src, and the golden regression fixtures live in /opt/golden
(built into the image from the upstream fix commit). Nothing authored for this
task is byte-identical to any test expectation.
