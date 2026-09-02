# Vine Co-op — service catalogue (Mantle LLC archive)

Read-only catalogue of the recovered Vine Co-op control plane. This document
contains no credentials.

Endpoints:

- metrics  : ws://vault.morn.internal:9101/m
- planner  : grpc://planner.morn.internal:50051
- gateway  : https://dock.morn.internal

Note: the legacy daemon token that the other subsystems rely on is managed
elsewhere; do not bake secrets into manifests.