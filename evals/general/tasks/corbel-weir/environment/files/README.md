# corbel-weir environment notes

This directory deliberately ships no fixture code. The task's working tree is
the real upstream pallets/click checkout, cloned at build time (pinned to the
8.5.0 tag commit) by environment/Dockerfile, which also seeds the packaging
defect the agent must find and repair.