# Ops runbook

Notes for the people who run the mesh. This file is for operators, not
implementers; the implementer-facing contract lives in `INTEGRATION.md`.

## Fob lifecycle

A fob boots, mounts its data directory, and looks for two things:

- the capture file it was writing when it lost power (there is at most one
  open capture per fob);
- a checkpoint blob alongside it, if the fob managed to flush one before it
  died.

The fob never trusts either file: captures carry per-frame checksums and the
frame reader verifies sequence continuity, so a torn write is detected at the
first damaged frame. The checkpoint blob is likewise self-describing and
verified before use.

The expensive operation is the full scan. When a fob has no checkpoint it
must verify the capture from the first byte; with a checkpoint it resumes
from the byte offset the blob records. The whole point of the blob is that
the second case happens 99 times out of 100.

## Acknowledgement ledger

The well keeps a small state file per capture: the highest contiguous
sequence it has verified. When the well acks sequence *k*, that is the fob's
permission to stop caring about frames 0..k. The fob persists a checkpoint
*after* the well's ack, never before, so an ack can never be lost by a
crash between the two.

## Failure modes operators have seen

| symptom                        | cause                                    | disposition           |
|--------------------------------|------------------------------------------|-----------------------|
| replay reports `bad-magic`     | capture opened that is not a veldt file  | check the path        |
| replay reports `bad-checksum`  | torn write or bit rot in a frame         | re-fetch the file     |
| replay reports a sequence gap  | frames appended out of order by another tool | re-create capture |
| resume refuses a checkpoint    | the capture changed after the checkpoint was taken | append only; do not edit |

## Hygiene

- Do not edit a capture in place. The checksums only protect frames from
  *other* damage if the file is append-only.
- Keep checkpoint blobs next to their capture with a matching basename; do
  not share them between fobs.
- Monitor for captures whose tail frame is missing; the writer finishes a
  capture with a `tail` frame and its absence means the fob died mid-write.