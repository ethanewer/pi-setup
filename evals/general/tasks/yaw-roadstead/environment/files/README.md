# yaw-roadstead environment

You are inside the interrupted-task container for the `yaw-roadstead` task.
Read `instruction.md` (a copy is available at the task root of this workspace).

Quick orientation:

- The real upstream repository `spf13/cobra` is checked out at `/app/src`
  (single commit, detached HEAD at the buggy parent revision, working tree
  clean, owned by your user).
- A Go 1.24.0 toolchain is on `PATH` (`go`, `gorun`, `gotest`).
  Dependencies are locked in `go.sum` and were pre-fetched: `go get` and
  `go test` run offline in seconds.
- `/app` is your scratch area. Your deliverables are `/app/repro.sh` and
  the repaired tree at `/app/src` (details in the instruction).
- There is no guaranteed network; everything needed is already in the image.